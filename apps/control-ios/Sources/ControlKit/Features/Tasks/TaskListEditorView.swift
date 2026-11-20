import SwiftUI

/// Qué campos del editor de listas se pueden tocar (D-024, Q8). Nombre, color y orden son
/// owner-only en el servidor: sin red, quien no es propietario no los edita (encolar ese cambio
/// acabaría descartado con un 403). Si sin red no se conocen los miembros, tampoco.
enum TaskListEditorFields {
    /// - Parameters:
    ///   - isEditing: edición de una lista existente (en un alta siempre se puede).
    ///   - isLocalList: lista creada offline aún sin sincronizar (es de quien la creó).
    ///   - isOnline: con red, el servidor decide como siempre.
    ///   - isOwner: `nil` = miembros desconocidos.
    static func ownerFieldsEnabled(isEditing: Bool, isLocalList: Bool, isOnline: Bool, isOwner: Bool?) -> Bool {
        guard isEditing, !isLocalList, !isOnline else { return true }
        return isOwner == true
    }

    /// «Eliminar lista» (solo en edición). Borrar es owner-only en el servidor; encolar el borrado de
    /// un no propietario quitaría de la cola las ops de sus tareas y luego acabaría en 403 (R1-03).
    /// Se encola sin red y también con red si la cola del hogar no está vacía (FIFO, R8; R2-02), así
    /// que en ambos casos solo lo permite al propietario (o en una lista creada offline).
    /// - Parameter pendingCount: ops en la cola del hogar.
    static func deleteEnabled(isLocalList: Bool, isOnline: Bool, isOwner: Bool?, pendingCount: Int) -> Bool {
        ownerFieldsEnabled(isEditing: true, isLocalList: isLocalList, isOnline: isOnline && pendingCount == 0, isOwner: isOwner)
    }
}

/// Editor de lista de tareas (alta/edición): nombre, color, orden y flags `widget`/`dashboard`
/// propios. El borrado de la lista vive aquí (owner-only en el servidor).
struct TaskListEditorView: View {
    @Bindable var store: TasksStore
    let editing: TaskListEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: Color
    @State private var sort: String
    @State private var widget: Bool
    @State private var dashboard: Bool
    @State private var showDeleteConfirm = false
    @State private var isWorking = false

    private static let sortOptions = [
        (id: "updated_at", title: "Fecha de actualización"),
        (id: "title", title: "Título"),
        (id: "custom", title: "Personalizado")
    ]

    init(store: TasksStore, editing: TaskListEntry?) {
        self.store = store
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: Color(hex: editing?.color ?? Palette.fallbackItem))
        _sort = State(initialValue: editing?.sort ?? "updated_at")
        _widget = State(initialValue: editing?.showsInWidget ?? true)
        _dashboard = State(initialValue: editing?.showsInDashboard ?? true)
    }

    private var isLocalList: Bool { editing.map { store.resolve($0.id) < 0 } ?? false }
    private var isOnline: Bool { !DataFreshness.shared.isOffline }
    private var isOwner: Bool? {
        store.members.isEmpty ? nil : AccessRoster.callerIsOwner(store.currentUserId, in: store.members)
    }

    /// Nombre, color y orden editables (ver `TaskListEditorFields`).
    private var ownerFieldsEnabled: Bool {
        TaskListEditorFields.ownerFieldsEnabled(isEditing: editing != nil, isLocalList: isLocalList, isOnline: isOnline, isOwner: isOwner)
    }

    /// «Eliminar lista» habilitado (ver `TaskListEditorFields.deleteEnabled`).
    private var deleteEnabled: Bool {
        TaskListEditorFields.deleteEnabled(isLocalList: isLocalList, isOnline: isOnline, isOwner: isOwner,
                                           pendingCount: store.outbox?.pendingCount ?? 0)
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Lista", systemImage: "list.bullet") {
                HomitaField(placeholder: "Nombre", text: $name)
                    .disabled(!ownerFieldsEnabled)
                HomitaColorField(title: "Color", color: $color)
                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                    .disabled(!ownerFieldsEnabled)
                if !ownerFieldsEnabled {
                    HomitaFootnote(text: "Sin conexión, solo quien creó la lista puede cambiar el nombre, el color y el orden.")
                }
            }
            HomitaPanel("Orden de las tareas", systemImage: "arrow.up.arrow.down") {
                HomitaRadioGroup(selection: Binding(get: { sort }, set: { sort = $0 ?? sort }), items: Self.sortOptions)
                    .disabled(!ownerFieldsEnabled)
                if sort == "custom" {
                    HomitaFootnote(text: "Podrás reordenar las tareas con el botón Editar.")
                }
            }
            HomitaPanel("Visible en", systemImage: "eye") {
                HomitaToggle(title: "Widget", isOn: $widget)
                HomitaToggle(title: "Dashboard", isOn: $dashboard)
            }
            HomitaButton(
                title: editing == nil ? "Crear lista" : "Guardar",
                isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking,
                isLoading: isWorking
            ) {
                Task { await save() }
            }
            if editing != nil {
                HomitaButton(title: "Eliminar lista", kind: .secondary, isEnabled: deleteEnabled && !isWorking) {
                    showDeleteConfirm = true
                }
                if !deleteEnabled {
                    HomitaFootnote(text: isOnline
                        ? "Hay cambios pendientes de sincronizar; hasta que terminen, solo quien creó la lista puede eliminarla."
                        : "Sin conexión, solo quien creó la lista puede eliminarla.")
                }
            }
        }
        .navigationTitle(editing == nil ? "Nueva lista" : "Editar lista")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
        .homitaConfirm("Se eliminará la lista y todas sus tareas.", isPresented: $showDeleteConfirm, confirmTitle: "Eliminar lista") {
            Task { await delete() }
        }
        .errorAlert($store.errorMessage)
        // «Reintentar» que va bien cierra el editor, igual que un guardado correcto.
        .writeFailureToast($store.writeFailure) { dismiss() }
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        let ok = await store.saveList(
            name: name.trimmingCharacters(in: .whitespaces),
            color: color.hexString,
            sort: sort,
            widget: widget,
            dashboard: dashboard,
            editing: editing
        )
        if ok { dismiss() }
    }

    private func delete() async {
        guard let editing else { return }
        isWorking = true
        defer { isWorking = false }
        await store.deleteList(editing)
        dismiss()
    }
}
