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

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Tarea", systemImage: "checklist") {
                HomitaField(placeholder: "Título", text: $title)
                if task == nil {
                    Text("Lista")
                        .font(HomitaFont.geist(14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                    HomitaRadioGroup(
                        selection: Binding(get: { listId }, set: { listId = $0 ?? listId }),
                        items: taskLists.map { (id: $0.id, title: $0.name) }
                    )
                }
            }
            HomitaButton(title: task == nil ? "Crear tarea" : "Guardar", isEnabled: canSave) {
                onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), listId)
                dismiss()
            }
            if let onDelete {
                HomitaButton(title: "Eliminar tarea", kind: .secondary) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(task == nil ? "Nueva tarea" : "Editar tarea")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
    }
}
