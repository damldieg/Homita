import SwiftUI

/// Pestaña Tareas: segmento "Tareas" (global con filtro por lista) / "Listas".
public struct TasksRootView: View {
    let services: AppServices
    @State private var store: TasksStore
    @State private var segment = 0
    /// Lista pedida desde Inicio («Ver más»): se despliega solo esa y se pliegan las demás.
    @Binding var listRequest: Int?

    public init(services: AppServices, listRequest: Binding<Int?> = .constant(nil)) {
        self.services = services
        _listRequest = listRequest
        _store = State(initialValue: TasksStore(taskLists: services.taskLists, tasks: services.tasks, persons: services.persons))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HomitaSegmented(selection: $segment, items: [(id: 0, title: "Tareas"), (id: 1, title: "Listas")])
                    .padding([.horizontal, .top])

                if segment == 0 {
                    TasksView(store: store, expandRequest: $listRequest)
                } else {
                    TaskListsView(store: store)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(segment == 0 ? "Tareas" : "Listas")
            .task {
                await store.loadLists()
                await store.loadTasks()
                await store.loadPersons()
            }
            .onChange(of: listRequest, initial: true) { _, id in
                // Muestra todas las listas (sin filtro); TasksView pliega las demás.
                guard id != nil else { return }
                segment = 0
                if store.listFilterId != nil {
                    store.listFilterId = nil
                    Task { await store.loadTasks() }
                }
            }
            .errorAlert($store.errorMessage)
            .writeFailureToast($store.writeFailure)
        }
    }
}

/// Tareas globales: filtro por lista, pendientes/completadas, completar, reordenar (solo con
/// `sort=custom` en la lista activa) y alta rápida.
struct TasksView: View {
    @Bindable var store: TasksStore
    @Binding var expandRequest: Int?
    @State private var newTaskTitle = ""
    @State private var showCreateTask = false
    @State private var pendingTaskDelete: [TaskEntry] = []
    @State private var showTaskDelete = false
    @State private var showCompletedDelete = false
    @State private var completedListId: Int?
    @State private var completedNames: [String] = []
    @State private var taskToEdit: TaskEntry?
    /// Listas plegadas; por defecto todas desplegadas.
    @State private var collapsedListIds: Set<Int> = []
    #if os(iOS)
    // EditMode solo existe en iOS: en macOS el drag de `.onMove` funciona sin modo edición.
    @State private var editMode: EditMode = .inactive
    #endif

    /// Hay alguna tarea visible (pendiente o completada); excluyente con el estado vacío.
    private var hasTasks: Bool {
        !store.pendingTasks.isEmpty || !store.completedTasks.isEmpty
    }

    /// Despliega solo la lista pedida y pliega el resto (cuando ya hay grupos cargados).
    private func applyExpandRequest() {
        // Solo con los grupos completos: tras la primera carga, sin filtro y sin recarga en curso.
        guard let id = expandRequest, store.hasLoadedTasks, store.listFilterId == nil, !store.isLoading else { return }
        collapsedListIds = Set(store.taskGroups.map(\.listId)).subtracting([id])
        expandRequest = nil
    }

    /// Encabezado de un grupo (AJ/Tareas): plegar, nombre, x/9 y papelera de completadas.
    private func groupHeader(_ group: TaskGroup) -> some View {
        HStack(spacing: 8) {
            Button {
                if collapsedListIds.contains(group.listId) {
                    collapsedListIds.remove(group.listId)
                } else {
                    collapsedListIds.insert(group.listId)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsedListIds.contains(group.listId) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                    HomitaSectionHeader(
                        title: group.name,
                        count: nil,
                        countText: "\(group.tasks.filter(\.isCompleted).count)/\(group.count)",
                        tint: Color(hex: group.colorHex ?? Palette.accentHex)
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(group.tasks.filter(\.isCompleted).count) de \(group.count) completadas")
            .accessibilityValue(collapsedListIds.contains(group.listId) ? "plegada" : "desplegada")
            Spacer(minLength: 0)
            // Borra solo las completadas de esta lista, con confirmación.
            if group.tasks.contains(where: \.isCompleted) {
                Button {
                    completedListId = group.listId
                    completedNames = group.tasks.filter(\.isCompleted).map(\.title)
                    showCompletedDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Eliminar tareas completadas de \(group.name)")
            }
        }
    }

    var body: some View {
        List {
            if store.listFilterId != nil {
                HomitaCard {
                    HStack(spacing: 10) {
                        HomitaField(placeholder: "Nueva tarea", text: $newTaskTitle)
                        Button {
                            Task {
                                // Si la escritura falla se conserva lo escrito (toast con «Reintentar»).
                                if await store.createTask(title: newTaskTitle, listId: store.listFilterId ?? 0) {
                                    newTaskTitle = ""
                                }
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

            ForEach(store.taskGroups) { group in
                Section {
                    groupHeader(group)
                        .listRowBackground(GroupRowBackground(first: true, last: collapsedListIds.contains(group.listId)))
                        .listRowSeparator(.hidden)
                    if !collapsedListIds.contains(group.listId) {
                        ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                            TaskRow(task: task, showListName: false, plain: true) {
                                Task { await store.toggleComplete(task) }
                            } onEdit: {
                                taskToEdit = task
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(GroupRowBackground(first: false, last: index == group.tasks.count - 1))
                            .listRowSeparator(index == group.tasks.count - 1 ? .hidden : .visible, edges: .bottom)
                            .listRowSeparatorTint(Palette.line)
                        }
                        .onDelete { indexSet in
                            pendingTaskDelete = indexSet.map { group.tasks[$0] }
                            showTaskDelete = true
                        }
                        .onMove { source, destination in
                            // Reordenar solo con lista activa en orden personalizado (un único grupo).
                            guard store.canReorder, let from = source.first else { return }
                            let task = group.tasks[from]
                            guard !task.isCompleted else { return }
                            Task { await store.movePendingTask(id: task.id, to: destination) }
                        }
                    }
                }
            }

            if !store.hasLoadedTasks || (store.isLoading && !hasTasks) {
                HomitaSkeletonRows(count: 3, height: 56, label: "Cargando tareas").homitaRow()
            }
            if store.hasLoadedTasks && !hasTasks && !store.isLoading {
                HomitaEmptyState(.tasks(filtered: store.listFilterId != nil)) {
                    showCreateTask = true
                }
                .homitaRow()
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.s3)
        #endif
        .homitaList()
        .onChange(of: expandRequest, initial: true) { applyExpandRequest() }
        .onChange(of: store.hasLoadedTasks) { applyExpandRequest() }
        .onChange(of: store.isLoading) { applyExpandRequest() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreateTask = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("Nueva tarea")
                .accessibilityIdentifier("tareas.alta")
            }
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
                TaskEditorView(taskLists: store.taskLists, persons: store.persons, task: nil,
                               writeFailure: $store.writeFailure) { title, listId, personIds in
                    await store.createTask(title: title, listId: listId, personIds: personIds)
                }
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
        }
        .homitaConfirm(DeleteConfirmation.message(names: pendingTaskDelete.map(\.title), consequence: "Se eliminará la tarea."), isPresented: $showTaskDelete, confirmTitle: "Eliminar") {
            let tasks = pendingTaskDelete
            Task { for task in tasks { await store.deleteTask(task) } }
        }
        .homitaConfirm(DeleteConfirmation.message(names: completedNames, consequence: "Se eliminarán las tareas completadas de esta lista."), isPresented: $showCompletedDelete, confirmTitle: "Eliminar") {
            if let id = completedListId { Task { await store.deleteCompleted(listId: id) } }
        }
        .overlay {
            // Bloquea la interacción mientras se borran las completadas.
            if store.isDeletingCompleted {
                HomitaLoadingOverlay(message: "Eliminando completadas…")
            }
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
                HomitaSkeletonRows(count: 3, height: 64, label: "Cargando listas").homitaRow()
            }
            if store.hasLoadedLists && store.taskLists.isEmpty && !store.isLoading {
                HomitaEmptyState(.taskLists) {
                    showCreateList = true
                }
                .homitaRow()
            }
            if !store.taskLists.isEmpty {
            Section {
                // E2-06: orden por nombre (no alfabético de servidor).
                ForEach(store.taskLists.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }, id: \.id) { list in
                    NavigationLink {
                        TaskListDetailView(store: store, list: list)
                    } label: {
                        HomitaCard {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: list.color))
                                    .frame(width: 14, height: 14)
                                Text(list.name)
                                    .font(HomitaFont.inter(17, weight: .semibold, relativeTo: .body))
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
            }
        }
        .homitaList()
        .safeAreaInset(edge: .bottom) {
            if !store.taskLists.isEmpty {
                HomitaFloatingAddButton(title: "Nueva lista") { showCreateList = true }
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

/// Fila de tarea como tarjeta: casilla para completar y toque para editar.
/// Fondo blanco de una fila dentro de una tarjeta de grupo: redondea solo la primera y la última
/// fila, así el grupo se ve como una tarjeta continua (el contenedor del sistema no pinta el color).
struct GroupRowBackground: View {
    var first: Bool
    var last: Bool

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: first ? Radius.lg : 0,
            bottomLeadingRadius: last ? Radius.lg : 0,
            bottomTrailingRadius: last ? Radius.lg : 0,
            topTrailingRadius: first ? Radius.lg : 0,
            style: .continuous
        )
        .fill(Palette.surface)
    }
}

struct TaskRow: View {
    let task: TaskEntry
    let showListName: Bool
    /// Fila plana dentro de la tarjeta de su lista (wireframe): sin tarjeta propia.
    var plain: Bool = false
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
        let row = HStack(spacing: 12) {
            HomitaCheckbox(isOn: task.isCompleted, tintHex: Palette.onlineHex, onChange: onToggle)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(task.isCompleted ? Palette.inkMuted : Palette.ink)
                    .strikethrough(task.isCompleted)
                AssignedPersonTags(persons: task.persons)
                if showListName, let name = task.task_list_name {
                    HomitaBadge(title: name, tintHex: task.task_list_color ?? Palette.accentHex)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        return Group {
            if plain {
                row.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HomitaCard { row }
            }
        }
    }
}

/// Botón de añadir fijo al pie de la lista (no obliga a llegar al final del scroll).
struct HomitaFloatingAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(HomitaFont.inter(17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Palette.onFill)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Palette.accent, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}
