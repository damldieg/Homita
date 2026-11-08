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
        ("updated_at", "Fecha de actualización"),
        ("title", "Título"),
        ("custom", "Personalizado")
    ]

    init(store: TasksStore, editing: TaskListEntry?) {
        self.store = store
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: Color(hex: editing?.color ?? "#6923E2"))
        _sort = State(initialValue: editing?.sort ?? "updated_at")
        _widget = State(initialValue: editing?.showsInWidget ?? true)
        _dashboard = State(initialValue: editing?.showsInDashboard ?? true)
    }

    var body: some View {
        Form {
            Section("Lista") {
                TextField("Nombre", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
            Section("Orden de las tareas") {
                Picker("Orden", selection: $sort) {
                    ForEach(Self.sortOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                if sort == "custom" {
                    Text("Podrás reordenar las tareas con el botón Editar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Visible en") {
                Toggle("Widget", isOn: $widget)
                Toggle("Dashboard", isOn: $dashboard)
            }
            Section {
                Button(editing == nil ? "Crear lista" : "Guardar") {
                    Task { await save() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            if editing != nil {
                Section {
                    Button("Eliminar lista", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(editing == nil ? "Nueva lista" : "Editar lista")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
        .confirmationDialog(
            "Se eliminará la lista y todas sus tareas.",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Eliminar lista", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .errorAlert($store.errorMessage)
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
