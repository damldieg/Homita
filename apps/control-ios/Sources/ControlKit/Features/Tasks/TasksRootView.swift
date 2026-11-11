import SwiftUI

/// Pestaña Tareas: segmento "Tareas" (global con filtro por lista) / "Listas".
public struct TasksRootView: View {
    let services: AppServices
    @State private var store: TasksStore
    @State private var segment = 0

    public init(services: AppServices) {
        self.services = services
        _store = State(initialValue: TasksStore(taskLists: services.taskLists, tasks: services.tasks))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("Tareas").tag(0)
                    Text("Listas").tag(1)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if segment == 0 {
                    TasksView(store: store)
                } else {
                    TaskListsView(store: store)
                }
            }
            .navigationTitle(segment == 0 ? "Tareas" : "Listas")
            .task {
                await store.loadLists()
                await store.loadTasks()
            }
            .errorAlert($store.errorMessage)
        }
    }
}

/// Tareas globales: filtro por lista, pendientes/completadas, completar, reordenar (solo con
/// `sort=custom` en la lista activa) y alta rápida.
struct TasksView: View {
    @Bindable var store: TasksStore
    @State private var newTaskTitle = ""
    @State private var showCreateTask = false
    @State private var taskToEdit: TaskEntry?
    #if os(iOS)
    // EditMode solo existe en iOS: en macOS el drag de `.onMove` funciona sin modo edición.
    @State private var editMode: EditMode = .inactive
    #endif

    var body: some View {
        List {
            if store.listFilterId != nil {
                HStack {
                    TextField("Nueva tarea", text: $newTaskTitle)
                    Button {
                        Task {
                            await store.createTask(title: newTaskTitle, listId: store.listFilterId ?? 0)
                            newTaskTitle = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !store.pendingTasks.isEmpty {
                Section("Pendientes (\(store.pendingTasks.count))") {
                    ForEach(store.pendingTasks, id: \.id) { task in
                        TaskRow(task: task, showListName: store.listFilterId == nil) {
                            Task { await store.toggleComplete(task) }
                        } onEdit: {
                            taskToEdit = task
                        }
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.pendingTasks[$0] }
                        Task { for task in removed { await store.deleteTask(task) } }
                    }
                    .onMove { source, destination in
                        guard store.canReorder, let from = source.first else { return }
                        let task = store.pendingTasks[from]
                        Task { await store.movePendingTask(id: task.id, to: destination) }
                    }
                }
            }

            if !store.completedTasks.isEmpty {
                Section("Completadas (\(store.completedTasks.count))") {
                    ForEach(store.completedTasks, id: \.id) { task in
                        TaskRow(task: task, showListName: store.listFilterId == nil) {
                            Task { await store.toggleComplete(task) }
                        } onEdit: {
                            taskToEdit = task
                        }
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.completedTasks[$0] }
                        Task { for task in removed { await store.deleteTask(task) } }
                    }
                }
            }

            if store.pendingTasks.isEmpty && store.completedTasks.isEmpty && !store.isLoading {
                if store.listFilterId == nil {
                    Button("Nueva tarea") {
                        showCreateTask = true
                    }
                } else {
                    Text("Sin tareas")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Todas") {
                        store.listFilterId = nil
                        Task { await store.loadTasks() }
                    }
                    ForEach(store.taskLists, id: \.id) { list in
                        Button(list.name) {
                            store.listFilterId = list.id
                            Task { await store.loadTasks() }
                        }
                    }
                } label: {
                    Label("Filtrar", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            #if os(iOS)
            if store.canReorder {
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode == .active ? "OK" : "Editar") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .sheet(isPresented: $showCreateTask) {
            NavigationStack {
                TaskEditorView(taskLists: store.taskLists, task: nil) { title, listId in
                    Task { await store.createTask(title: title, listId: listId) }
                }
            }
        }
        .sheet(item: $taskToEdit) { task in
            NavigationStack {
                TaskEditorView(taskLists: store.taskLists, task: task) { title, _ in
                    Task { await store.updateTask(task, title: title) }
                } onDelete: {
                    Task { await store.deleteTask(task) }
                }
            }
        }
        .refreshable {
            await store.loadLists()
            await store.loadTasks()
        }
    }
}

/// Lista de listas: pendientes por lista, alta y navegación al detalle.
struct TaskListsView: View {
    @Bindable var store: TasksStore
    @State private var showCreateList = false

    var body: some View {
        List {
            ForEach(store.taskLists, id: \.id) { list in
                NavigationLink {
                    TaskListDetailView(store: store, list: list)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: list.color))
                            .frame(width: 12, height: 12)
                        Text(list.name)
                        Spacer()
                        Text("\(list.pendingTaskCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                showCreateList = true
            } label: {
                Label("Nueva lista", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showCreateList) {
            NavigationStack {
                TaskListEditorView(store: store, editing: nil)
            }
        }
        .refreshable {
            await store.loadLists()
        }
    }
}

/// Fila de tarea: completar/descompletar y toque para editar.
struct TaskRow: View {
    let task: TaskEntry
    let showListName: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                if showListName, let name = task.task_list_name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityAction(named: "Editar", onEdit)
    }
}
