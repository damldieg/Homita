import SwiftUI

/// Editor de tarea (alta/edición). En alta elige lista; en edición solo cambia el título, las
/// personas y la prioridad (mover de lista no existe en el contrato v1). La prioridad (0037) arranca
/// en Media al crear y en la de la tarea al editar. El guard de título duplicado lo hace el store.
/// Se cierra solo si `onSave` devuelve que la escritura fue bien; si falla conserva lo escrito y
/// muestra el toast del store (`writeFailure`) con «Reintentar», como el editor de persona.
struct TaskEditorView: View {
    let taskLists: [TaskListEntry]
    let persons: [PersonEntry]
    let task: TaskEntry?
    /// Último fallo de escritura del store, para el toast dentro de la hoja.
    @Binding var writeFailure: WriteFailure?
    /// Guarda (título recortado, lista, personas, prioridad) y devuelve si fue bien.
    let onSave: (String, Int, [Int], TaskPriority, String?) async -> Bool
    let onDelete: (() -> Void)?
    /// Permisos de la lista de la tarea (la tarea hereda el ACL de su lista). Solo en edición.
    let access: TaskListAccess?
    /// Personas asignables al crear en una lista (0038: con cuenta y acceso). nil = `persons` tal cual.
    let assignable: ((Int) -> [PersonEntry])?
    /// Carga lo que necesita `assignable` para una lista (se llama al elegir lista). Devuelve si la
    /// carga dejó roster (personas y miembros); si no, la selección no se poda.
    let loadAssignable: ((Int) async -> Bool)?
    /// Lista fijada al abrir el alta desde la cabecera de un grupo; con ella no se elige lista.
    let lockedListId: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    /// El error de título aparece solo después de que el usuario toque el campo.
    @State private var titleTouched = false
    @State private var showDeleteConfirm = false
    @State private var listId: Int
    @State private var personIds: [Int]
    @State private var priority: TaskPriority
    /// Fecha límite (0041): `hasDue` = la tarea tiene fecha; `dueDate` = la que muestra el selector.
    @State private var hasDue: Bool
    @State private var dueDate: Date
    /// Fecha que tenía la tarea al abrir el editor (nil = sin fecha). Para no reenviar una fecha sin cambios.
    private let initialDue: Date?
    @State private var isSaving = false

    init(
        taskLists: [TaskListEntry],
        persons: [PersonEntry] = [],
        task: TaskEntry?,
        writeFailure: Binding<WriteFailure?>,
        access: TaskListAccess? = nil,
        assignable: ((Int) -> [PersonEntry])? = nil,
        loadAssignable: ((Int) async -> Bool)? = nil,
        initialListId: Int? = nil,
        onSave: @escaping (String, Int, [Int], TaskPriority, String?) async -> Bool,
        onDelete: (() -> Void)? = nil
    ) {
        self.access = access
        self.assignable = assignable
        self.loadAssignable = loadAssignable
        self.taskLists = taskLists
        self.persons = persons
        self.task = task
        _writeFailure = writeFailure
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task?.title ?? "")
        let resolved = Self.resolveListId(task: task, initialListId: initialListId, taskLists: taskLists)
        lockedListId = resolved.isLocked ? resolved.listId : nil
        _listId = State(initialValue: resolved.listId)
        _personIds = State(initialValue: task?.persons?.map(\.id) ?? [])
        _priority = State(initialValue: task?.priorityValue ?? .media)
        let due = TaskDue.date(task?.due_at)
        initialDue = due
        _hasDue = State(initialValue: due != nil)
        _dueDate = State(initialValue: due ?? Date().addingTimeInterval(24 * 3600))
    }

    /// Lista inicial: en edición la de la tarea; en alta la fijada si existe (bloqueada); si no, la primera.
    static func resolveListId(task: TaskEntry?, initialListId: Int?, taskLists: [TaskListEntry]) -> (listId: Int, isLocked: Bool) {
        if let task { return (task.task_list_id, false) }
        if let initialListId, taskLists.contains(where: { $0.id == initialListId }) {
            return (initialListId, true)
        }
        return (taskLists.first?.id ?? 0, false)
    }

    /// Sin listas no hay dónde crear la tarea: en alta hace falta al menos una lista.
    private var hasTarget: Bool {
        task != nil || !taskLists.isEmpty
    }

    /// El selector se filtra en el alta y al editar una tarea aún local: el update se funde en el
    /// create pendiente (`OutboxCompactor`) y para el servidor será un `create_task`. En la edición
    /// de una tarea remota se ofrecen todas (`update_task` no restringe, P-2/AC-6).
    private var filtersAssignees: Bool {
        assignable != nil && (task == nil || (task?.id ?? 0) < 0)
    }

    /// Personas que ofrece el selector.
    private var selectablePersons: [PersonEntry] {
        guard filtersAssignees, let assignable else { return persons }
        return assignable(listId)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasTarget && !isSaving
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Tarea", systemImage: "checklist") {
                HomitaFormField(
                    placeholder: "Título",
                    text: $title,
                    error: titleTouched ? TaskTitleValidation.message(for: title) : nil
                )
                .onChange(of: title) { _, _ in titleTouched = true }
                if task == nil {
                    if taskLists.isEmpty {
                        HomitaFootnote(text: "Todavía no tienes listas. Crea una en la pestaña Listas para añadir tareas.")
                    } else if lockedListId == nil {
                        Text("Lista")
                            .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSoft)
                        HomitaRadioGroup(
                            selection: Binding(get: { listId }, set: { listId = $0 ?? listId }),
                            items: taskLists.map { (id: $0.id, title: $0.name) }
                        )
                    }
                }
                Text("Prioridad")
                    .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
                HomitaSegmented(selection: $priority, items: TaskPriority.allCases.map { (id: $0, title: $0.label) })
                    .accessibilityIdentifier("tarea.prioridad")
                Toggle("Fecha límite", isOn: $hasDue)
                    .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
                    .accessibilityIdentifier("tarea.fecha.activa")
                if hasDue {
                    DatePicker("Vence", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("tarea.fecha")
                }
            }
            PersonSelector(
                persons: selectablePersons, selected: $personIds,
                emptyText: filtersAssignees ? "Nadie con cuenta y acceso a esta lista para asignar." : nil
            )
            if task != nil, let access {
                MembersSection(rows: access.rows, isOwner: access.isOwner, onSetAccess: access.onSetAccess,
                               showsInvites: false, onInvite: { _ in }, onRemove: { _ in })
            }
            HomitaButton(title: task == nil ? "Crear tarea" : "Guardar", isEnabled: canSave, isLoading: isSaving) {
                Task { await save() }
            }
            if let onDelete {
                HomitaButton(title: "Eliminar tarea", kind: .secondary) {
                    showDeleteConfirm = true
                }
            }
        }
        .homitaConfirm(DeleteConfirmation.message(names: [task?.title ?? title], consequence: "Se eliminará la tarea."), isPresented: $showDeleteConfirm, confirmTitle: "Eliminar") {
            onDelete?()
            dismiss()
        }
        // «Reintentar» que va bien cierra el editor, igual que un guardado correcto.
        .writeFailureToast($writeFailure) { dismiss() }
        .navigationTitle(task == nil ? "Nueva tarea" : "Editar tarea")
        // Al elegir (o cambiar) de lista: carga sus asignables y quita de la selección las que no lo son.
        // Sin roster (sin conexión y sin caché) no se poda: decide el servidor o el replay (R1-03).
        .task(id: listId) {
            guard filtersAssignees, let assignable else { return }
            let rosterLoaded = await loadAssignable?(listId) ?? false
            personIds = TaskAssignees.prune(selected: personIds, assignable: assignable(listId), rosterLoaded: rosterLoaded)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// Cierra solo si la escritura fue bien; si falla, el formulario conserva lo escrito.
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let ok = await onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), listId, personIds, priority, dueOutput())
        if ok { dismiss() }
    }

    /// Valor de fecha para el guardado: nil = no tocar; "" = borrar; fecha UTC = fijarla.
    private func dueOutput() -> String? {
        guard hasDue else { return initialDue == nil ? nil : "" }
        let formatted = TaskDue.format(dueDate)
        if let initialDue, TaskDue.format(initialDue) == formatted { return nil }
        return formatted
    }
}

/// Permisos de la lista a la que pertenece la tarea, para el editor de tarea (0029): el permiso se
/// cambia en la lista; aquí se ve y, si el usuario es owner de la lista, se cambia desde la tarea.
struct TaskListAccess {
    let rows: [AccessRow]
    let isOwner: Bool
    let onSetAccess: (Int, AccessLevel) -> Void
}
