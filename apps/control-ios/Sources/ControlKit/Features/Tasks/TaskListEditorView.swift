import SwiftUI

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

    var body: some View {
        HomitaForm {
            HomitaPanel("Lista", systemImage: "list.bullet") {
                HomitaField(placeholder: "Nombre", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
            }
            HomitaPanel("Orden de las tareas", systemImage: "arrow.up.arrow.down") {
                HomitaRadioGroup(selection: Binding(get: { sort }, set: { sort = $0 ?? sort }), items: Self.sortOptions)
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
                HomitaButton(title: "Eliminar lista", kind: .secondary) {
                    showDeleteConfirm = true
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
