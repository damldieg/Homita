import SwiftUI

/// Editor de tarea (alta/edición). En alta elige lista; en edición solo cambia el título
/// (mover de lista no existe en el contrato v1). El guard de título duplicado lo hace el store.
struct TaskEditorView: View {
    let taskLists: [TaskListEntry]
    let task: TaskEntry?
    let onSave: (String, Int) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var listId: Int

    init(
        taskLists: [TaskListEntry],
        task: TaskEntry?,
        onSave: @escaping (String, Int) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.taskLists = taskLists
        self.task = task
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task?.title ?? "")
        _listId = State(initialValue: task?.task_list_id ?? taskLists.first?.id ?? 0)
    }

    var body: some View {
        Form {
            Section("Tarea") {
                TextField("Título", text: $title)
                if task == nil {
                    Picker("Lista", selection: $listId) {
                        ForEach(taskLists, id: \.id) { list in
                            Text(list.name).tag(list.id)
                        }
                    }
                }
            }
            Section {
                Button("Guardar") {
                    onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), listId)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let onDelete {
                Section {
                    Button("Eliminar tarea", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(task == nil ? "Nueva tarea" : "Editar tarea")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }
}
