import SwiftUI

/// Detalle de una lista de tareas: sus tareas (completar, reordenar si `sort=custom`, alta
/// rápida) y las personas con acceso (invitar/quitar por email). La edición/borrado de la lista
/// va a `TaskListEditorView`.
struct TaskListDetailView: View {
    @Bindable var store: TasksStore
    let list: TaskListEntry

    @Environment(SessionStore.self) private var session
    @State private var newTaskTitle = ""
    @State private var pendingTaskDelete: [TaskEntry] = []
    @State private var showTaskDelete = false
    @State private var showCompletedDelete = false
    @State private var showEditList = false
    @State private var taskToEdit: TaskEntry?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    /// La lista recargada desde el store (tras editar); si no está, la recibida.
    private var current: TaskListEntry {
        store.taskLists.first { $0.id == list.id } ?? list
    }

    /// Tareas de esta lista (el store puede tener el filtro global activo: se filtra en cliente).
    private var listTasks: [TaskEntry] {
        store.tasks.filter { $0.task_list_id == current.id }
    }
    private var pending: [TaskEntry] { listTasks.filter { !$0.isCompleted } }
    private var completed: [TaskEntry] { listTasks.filter { $0.isCompleted } }
    private var canReorder: Bool { current.sort == "custom" }

    var body: some View {
        List {
            Section {
                HomitaCard {
                    HStack(spacing: 10) {
                        HomitaField(placeholder: "Nueva tarea", text: $newTaskTitle)
                        Button {
                            let title = newTaskTitle
                            newTaskTitle = ""
                            Task {
                                // Si la escritura falla se devuelve lo escrito al campo (si sigue vacío).
                                let ok = await store.createTask(title: title, listId: current.id)
                                if !ok, newTaskTitle.isEmpty { newTaskTitle = title }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .homitaRow()
            }

            if !pending.isEmpty {
                Section {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, task in
                        TaskRow(task: task, showListName: false, plain: true) {
                            Task { await store.toggleComplete(task) }
                        } onEdit: {
                            taskToEdit = task
                        }
                        .homitaRow()
                        .listRowBackground(GroupRowBackground(first: index == 0, last: index == pending.count - 1))
                        .listRowSeparator(index == pending.count - 1 ? .hidden : .visible, edges: .bottom)
                        .listRowSeparatorTint(Palette.line)
                    }
                    .onDelete { indexSet in
                        pendingTaskDelete = indexSet.map { pending[$0] }
                        showTaskDelete = true
                    }
                    .onMove { source, destination in
                        guard canReorder, let from = source.first else { return }
                        let task = pending[from]
                        Task { await store.movePendingTask(id: task.id, to: destination) }
                    }
                } header: {
                    HomitaSectionHeader(title: "Pendientes", count: pending.count, systemImage: "checklist")
                }
            }

            if !completed.isEmpty {
                Section {
                    ForEach(Array(completed.enumerated()), id: \.element.id) { index, task in
                        TaskRow(task: task, showListName: false, plain: true) {
                            Task { await store.toggleComplete(task) }
                        } onEdit: {
                            taskToEdit = task
                        }
                        .homitaRow()
                        .listRowBackground(GroupRowBackground(first: index == 0, last: index == completed.count - 1))
                        .listRowSeparator(index == completed.count - 1 ? .hidden : .visible, edges: .bottom)
                        .listRowSeparatorTint(Palette.line)
                    }
                    .onDelete { indexSet in
                        pendingTaskDelete = indexSet.map { completed[$0] }
                        showTaskDelete = true
                    }
                } header: {
                    HStack {
                        HomitaSectionHeader(title: "Completadas", count: completed.count, systemImage: "checkmark.circle", tint: Palette.online)
                        Spacer(minLength: 0)
                        // Borra todas las completadas de la lista, con confirmación.
                        Button {
                            showCompletedDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Eliminar todas las completadas")
                    }
                }
            }

            if listTasks.isEmpty {
                HomitaCard {
                    HomitaEmptyNote(text: HomitaEmptyNoteText.listTasks)
                }
                .homitaRow()
            }

            MembersSection(
                members: store.members,
                currentUserId: session.session?.id,
                onInvite: { email in
                    Task { await store.invite(listId: current.id, email: email) }
                },
                onRemove: { userId in
                    Task { await store.removeMember(listId: current.id, userId: userId) }
                }
            )
            .homitaRow()
        }
        .homitaList()
        .navigationTitle(current.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .homitaNavigationBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar lista") { showEditList = true }
                    .foregroundStyle(Palette.ink)
            }
            #if os(iOS)
            if canReorder {
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode == .active ? "OK" : "Reordenar") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                    .foregroundStyle(Palette.ink)
                }
            }
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .task {
            store.listFilterId = current.id
            await store.loadTasks()
            await store.loadMembers(listId: current.id)
        }
        // U5: el filtro de lista es de esta pantalla; al salir, el segmento Tareas vuelve a «Todas».
        .onDisappear { store.listFilterId = nil }
        .sheet(isPresented: $showEditList) {
            NavigationStack {
                TaskListEditorView(store: store, editing: current)
            }
        }
        .sheet(item: $taskToEdit) { task in
            NavigationStack {
                TaskEditorView(taskLists: store.taskLists, persons: store.persons, task: task,
                               writeFailure: $store.writeFailure) { title, _, personIds in
                    await store.updateTask(task, title: title, personIds: personIds)
                } onDelete: {
                    Task { await store.deleteTask(task) }
                }
            }
        }
        .refreshable {
            await store.loadLists()
            await store.loadTasks()
            await store.loadMembers(listId: current.id)
        }
        .errorAlert($store.errorMessage)
        .writeFailureToast($store.writeFailure)
        .overlay {
            // Bloquea la interacción mientras se borran las completadas.
            if store.isDeletingCompleted {
                HomitaLoadingOverlay(message: "Eliminando completadas…")
            }
        }
        .homitaConfirm(DeleteConfirmation.message(names: completed.map(\.title), consequence: "Se eliminarán las tareas completadas de esta lista."), isPresented: $showCompletedDelete, confirmTitle: "Eliminar") {
            let id = current.id
            Task { await store.deleteCompleted(listId: id) }
        }
        .homitaConfirm(DeleteConfirmation.message(names: pendingTaskDelete.map(\.title), consequence: "Se eliminará la tarea."), isPresented: $showTaskDelete, confirmTitle: "Eliminar") {
            let tasks = pendingTaskDelete
            Task { for task in tasks { await store.deleteTask(task) } }
        }
    }
}
