import SwiftUI

/// Editor de tarea (alta/edición). En alta elige lista; en edición solo cambia el título
/// (mover de lista no existe en el contrato v1). El guard de título duplicado lo hace el store.
struct TaskEditorView: View {
    let taskLists: [TaskListEntry]
    let persons: [PersonEntry]
    let task: TaskEntry?
    let onSave: (String, Int, [Int]) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var listId: Int
    @State private var personIds: [Int]

    init(
        taskLists: [TaskListEntry],
        persons: [PersonEntry] = [],
        task: TaskEntry?,
        onSave: @escaping (String, Int, [Int]) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.taskLists = taskLists
        self.persons = persons
        self.task = task
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task?.title ?? "")
        _listId = State(initialValue: task?.task_list_id ?? taskLists.first?.id ?? 0)
        _personIds = State(initialValue: task?.persons?.map(\.id) ?? [])
    }

    /// Sin listas no hay dónde crear la tarea: en alta hace falta al menos una lista.
    private var hasTarget: Bool {
        task != nil || !taskLists.isEmpty
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasTarget
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Tarea", systemImage: "checklist") {
                HomitaField(placeholder: "Título", text: $title)
                if task == nil {
                    if taskLists.isEmpty {
                        HomitaFootnote(text: "Todavía no tienes listas. Crea una en la pestaña Listas para añadir tareas.")
                    } else {
                        Text("Lista")
                            .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSoft)
                        HomitaRadioGroup(
                            selection: Binding(get: { listId }, set: { listId = $0 ?? listId }),
                            items: taskLists.map { (id: $0.id, title: $0.name) }
                        )
                    }
                }
            }
            PersonSelector(persons: persons, selected: $personIds)
            HomitaButton(title: task == nil ? "Crear tarea" : "Guardar", isEnabled: canSave) {
                onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), listId, personIds)
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
