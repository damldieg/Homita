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
                HomitaSegmented(selection: $segment, items: [(id: 0, title: "Tareas"), (id: 1, title: "Listas")])
                    .padding([.horizontal, .top])

                if segment == 0 {
                    TasksView(store: store)
                } else {
                    TaskListsView(store: store)
                }
            }
            .background(Palette.background.ignoresSafeArea())
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
                HomitaCard {
                    HStack(spacing: 10) {
                        HomitaField(placeholder: "Nueva tarea", text: $newTaskTitle)
                        Button {
                            Task {
                                await store.createTask(title: newTaskTitle, listId: store.listFilterId ?? 0)
                                newTaskTitle = ""
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

            if !store.pendingTasks.isEmpty {
                Section {
                    ForEach(store.pendingTasks, id: \.id) { task in
                        TaskRow(task: task, showListName: store.listFilterId == nil) {
                            Task { await store.toggleComplete(task) }
                        } onEdit: {
                            taskToEdit = task
                        }
                        .homitaRow()
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
                } header: {
                    HomitaSectionHeader(title: "Pendientes", count: store.pendingTasks.count, systemImage: "checklist")
                }
            }

            if !store.completedTasks.isEmpty {
                Section {
                    ForEach(store.completedTasks, id: \.id) { task in
                        TaskRow(task: task, showListName: store.listFilterId == nil) {
                            Task { await store.toggleComplete(task) }
                        } onEdit: {
                            taskToEdit = task
                        }
                        .homitaRow()
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.completedTasks[$0] }
                        Task { for task in removed { await store.deleteTask(task) } }
                    }
                } header: {
                    HomitaSectionHeader(title: "Completadas", count: store.completedTasks.count, systemImage: "checkmark.circle", tint: Palette.online)
                }
            }

            if !store.hasLoadedTasks || (store.isLoading && store.pendingTasks.isEmpty && store.completedTasks.isEmpty) {
                HomitaLoadingCard(message: "Cargando tareas…").homitaRow()
            }
            if store.hasLoadedTasks && store.pendingTasks.isEmpty && store.completedTasks.isEmpty && !store.isLoading {
                HomitaEmptyState(
                    illustration: .tasks,
                    title: "Sin tareas",
                    message: store.listFilterId == nil
                        ? "Crea tu primera tarea y ponle una lista para tenerla a mano."
                        : "Esta lista no tiene tareas todavía.",
                    actionTitle: "Nueva tarea"
                ) {
                    showCreateTask = true
                }
                .homitaRow()
            }
        }
        .homitaList()
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
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Filtrar")
                }
            }
            #if os(iOS)
            if store.canReorder {
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode == .active ? "OK" : "Editar") {
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
            if !store.hasLoadedLists || (store.isLoading && store.taskLists.isEmpty) {
                HomitaLoadingCard(message: "Cargando listas…").homitaRow()
            }
            if store.hasLoadedLists && store.taskLists.isEmpty && !store.isLoading {
                HomitaEmptyState(
                    illustration: .lists,
                    title: "Sin listas",
                    message: "Las listas agrupan tus tareas: compra, casa, trabajo…",
                    actionTitle: "Nueva lista"
                ) {
                    showCreateList = true
                }
                .homitaRow()
            }
            if !store.taskLists.isEmpty {
            Section {
                ForEach(store.taskLists, id: \.id) { list in
                    NavigationLink {
                        TaskListDetailView(store: store, list: list)
                    } label: {
                        HomitaCard {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: list.color))
                                    .frame(width: 14, height: 14)
                                Text(list.name)
                                    .font(HomitaFont.geist(17, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                HomitaBadge(title: "\(list.pendingTaskCount)", tintHex: list.color)
                            }
                        }
                    }
                    .homitaRow()
                }
            } header: {
                HomitaSectionHeader(title: "Listas", count: store.taskLists.count, systemImage: "list.bullet")
            }

            Section {
                Button {
                    showCreateList = true
                } label: {
                    HomitaCard {
                        Label("Nueva lista", systemImage: "plus")
                            .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .buttonStyle(.plain)
                .homitaRow()
            }
            }
        }
        .homitaList()
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

/// Fila de tarea como tarjeta: casilla para completar y toque para editar.
struct TaskRow: View {
    let task: TaskEntry
    let showListName: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: "Editar") { onEdit() }
    }

    private var rowContent: some View {
        HomitaCard {
            HStack(spacing: 12) {
                HomitaCheckbox(isOn: task.isCompleted, tintHex: Palette.onlineHex, onChange: onToggle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(task.isCompleted ? Palette.inkMuted : Palette.ink)
                        .strikethrough(task.isCompleted)
                    AssignedPersonsLine(persons: task.persons)
                    if showListName, let name = task.task_list_name {
                        HomitaBadge(title: name, tintHex: task.task_list_color ?? Palette.accentHex)
                            .padding(.top, 2)
                    }
                }
                Spacer()
            }
        }
    }
}
