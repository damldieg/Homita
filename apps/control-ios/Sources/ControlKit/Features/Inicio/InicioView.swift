import SwiftUI

/// Pestaña Inicio (versión mínima): saludo y fecha, Hoy · Eventos, Tareas pendientes, Rutinas de
/// hoy y accesos rápidos. Solo lee `event`, `task` y `routine`; las rutinas se calculan en cliente.
/// La casilla de las tareas completa/reabre igual que en la pestaña Tareas.
public struct InicioView: View {
    let services: AppServices
    @State private var store: InicioStore
    @State private var eventStore: EventStore
    @State private var calendarStore: CalendarStore
    @State private var personStore: PersonStore
    @State private var showTaskEditor = false
    @State private var showEventEditor = false

    public init(services: AppServices) {
        self.services = services
        _store = State(initialValue: InicioStore(
            events: services.events, tasks: services.tasks,
            routines: services.routines, taskLists: services.taskLists
        ))
        _eventStore = State(initialValue: EventStore(repo: services.events))
        _calendarStore = State(initialValue: CalendarStore(repo: services.calendars))
        _personStore = State(initialValue: PersonStore(repo: services.persons))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    greeting
                    eventsCard
                    tasksCard
                    routinesCard
                    quickActions
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .homitaNavigationBar()
            .refreshable { await store.load() }
            .task { await store.load() }
            .errorAlert($store.errorMessage)
            .sheet(isPresented: $showTaskEditor) {
                NavigationStack {
                    TaskEditorView(taskLists: store.taskLists, task: nil) { title, listId in
                        Task { await store.createTask(title: title, listId: listId) }
                    }
                }
            }
            .sheet(isPresented: $showEventEditor, onDismiss: { Task { await store.loadEvents() } }) {
                NavigationStack {
                    EventDetailView(store: eventStore, calendars: calendarStore, persons: personStore, event: nil)
                }
            }
        }
    }

    // MARK: - Saludo

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(HomitaFont.geist(34, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(Palette.ink)
            Text(dateText)
                .font(HomitaFont.geist(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var greetingText: String {
        let name = services.session.session?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Hola" : "Hola, \(name)"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: Date()).capitalizedFirst
    }

    // MARK: - Secciones

    private var eventsCard: some View {
        sectionCard(title: "Hoy · Eventos", systemImage: "calendar", count: store.todayEvents.count,
                    state: store.eventsState, retry: { await store.loadEvents() }) {
            if store.todayEvents.isEmpty {
                emptyText("Sin eventos hoy")
            }
            ForEach(store.todayEvents) { event in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: event.calendar_color ?? Palette.fallbackItem))
                        .frame(width: 4, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                        if let name = event.calendar_name {
                            Text(name)
                                .font(HomitaFont.geist(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    Spacer()
                    Text(Self.time(of: event.date_at))
                        .font(HomitaFont.geist(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkSoft)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var tasksCard: some View {
        sectionCard(title: "Tareas pendientes", systemImage: "checklist", count: store.pendingTasks.count,
                    state: store.tasksState, retry: { await store.loadTasks() }) {
            if store.pendingTasks.isEmpty {
                emptyText("Sin tareas pendientes")
            }
            ForEach(store.pendingTasks) { task in
                HStack(spacing: 12) {
                    HomitaCheckbox(isOn: task.isCompleted, tintHex: Palette.onlineHex) {
                        Task { await store.toggleComplete(task) }
                    }
                    Text(task.title)
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if let name = task.task_list_name {
                        HomitaBadge(title: name, tintHex: task.task_list_color ?? Palette.accentHex)
                    }
                }
            }
        }
    }

    private var routinesCard: some View {
        sectionCard(title: "Rutinas de hoy", systemImage: "repeat", count: store.todayRoutines.count,
                    state: store.routinesState, retry: { await store.loadRoutines() }) {
            if store.todayRoutines.isEmpty {
                emptyText("Sin rutinas hoy")
            }
            ForEach(store.todayRoutines) { routine in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: routine.calendar_color ?? Palette.fallbackItem))
                        .frame(width: 4, height: 28)
                    Text(routine.title)
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(String(routine.time.prefix(5)))
                        .font(HomitaFont.geist(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkSoft)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCESOS RÁPIDOS")
                .font(HomitaFont.geist(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
            HStack(spacing: 12) {
                HomitaButton(title: "+ Tarea") {
                    Task {
                        await store.loadTaskLists()
                        if store.taskLists.isEmpty {
                            if store.errorMessage == nil { store.errorMessage = "Crea una lista de tareas primero" }
                        } else {
                            showTaskEditor = true
                        }
                    }
                }
                HomitaButton(title: "+ Evento", kind: .secondary) {
                    Task {
                        await calendarStore.load()
                        await personStore.load()
                        if calendarStore.calendars.isEmpty {
                            store.errorMessage = calendarStore.errorMessage ?? "Crea un calendario primero"
                        } else {
                            showEventEditor = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Piezas

    private func sectionCard<Content: View>(
        title: String, systemImage: String, count: Int, state: InicioSectionState,
        retry: @escaping () async -> Void, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HomitaSectionHeader(title: title, count: state == .loaded ? count : nil, systemImage: systemImage)
            switch state {
            case .idle, .loading:
                if count == 0 {
                    Text("Cargando…")
                        .font(HomitaFont.geist(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    content()
                }
            case .failed(let message):
                Text(message)
                    .font(HomitaFont.geist(15, relativeTo: .body))
                    .foregroundStyle(Palette.accent)
                HomitaButton(title: "Reintentar", kind: .secondary) { Task { await retry() } }
            case .loaded:
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(HomitaFont.geist(15, relativeTo: .body))
            .foregroundStyle(Palette.inkSoft)
    }

    /// «HH:mm» de un `date_at` (`Y-m-d H:i:s`); si no se puede leer, el texto original.
    static func time(of dateAt: String) -> String {
        guard dateAt.count >= 16 else { return dateAt }
        let start = dateAt.index(dateAt.startIndex, offsetBy: 11)
        let end = dateAt.index(dateAt.startIndex, offsetBy: 16)
        return String(dateAt[start..<end])
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
