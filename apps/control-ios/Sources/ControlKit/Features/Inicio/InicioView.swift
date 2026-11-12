import SwiftUI

/// Destino de las flechas de las tarjetas de Inicio.
public enum InicioDestination: Sendable {
    case tasks, routines, events, home
    /// Pestaña Tareas filtrada por esta lista.
    case taskList(Int)
}

/// Pestaña Inicio (versión mínima): saludo y fecha, Hoy · Eventos, Tareas pendientes, Rutinas de
/// hoy y accesos rápidos. Solo lee `event`, `task` y `routine`; las rutinas se calculan en cliente.
/// La casilla de las tareas completa/reabre igual que en la pestaña Tareas.
public struct InicioView: View {
    let services: AppServices
    /// Navegación a otra pestaña (Tareas, Rutinas, Eventos); la resuelve `MainTabView`.
    var onOpen: (InicioDestination) -> Void = { _ in }
    @State private var store: InicioStore
    @State private var eventStore: EventStore
    @State private var calendarStore: CalendarStore
    @State private var personStore: PersonStore
    @State private var showTaskEditor = false
    @State private var showEventEditor = false
    /// Lista mostrada en la tarjeta de tareas (`nil` = la primera).
    @State private var taskPageId: Int?

    public init(services: AppServices, onOpen: @escaping (InicioDestination) -> Void = { _ in }) {
        self.services = services
        self.onOpen = onOpen
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
                    eventsCard.accessibilityIdentifier("inicio.tarjeta.eventos")
                    tasksCard.accessibilityIdentifier("inicio.tarjeta.tareas")
                    routinesCard.accessibilityIdentifier("inicio.tarjeta.rutinas")
                    quickActions.accessibilityIdentifier("inicio.accesos")
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .homitaHiddenNavigationBar()
            .refreshable { await store.load() }
            .task { await store.load() }
            .errorAlert($store.errorMessage)
            .writeFailureToast($store.writeFailure)
            .sheet(isPresented: $showTaskEditor) {
                NavigationStack {
                    TaskEditorView(taskLists: store.taskLists, task: nil,
                                   writeFailure: $store.writeFailure) { title, listId, _ in
                        await store.createTask(title: title, listId: listId)
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
        HomitaHeader(title: greetingText, subtitle: dateText) {
            HomitaHeaderButton(systemImage: "house", label: "Ir a Hogar") { onOpen(.home) }
        }
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
        sectionCard(title: "Hoy · Eventos", systemImage: "calendar", count: store.todayEvents.count, destination: .events,
                    state: store.eventsState, retry: { await store.loadEvents() }) {
            if store.todayEvents.isEmpty {
                emptyText(HomitaEmptyNoteText.todayEvents)
            }
            ForEach(Array(store.todayEvents.enumerated()), id: \.element.id) { index, event in
                if index > 0 { Divider().overlay(Palette.line) }
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: event.calendar_color ?? Palette.fallbackItem))
                        .frame(width: 4, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                        EventCountdownLabel(dateAt: event.date_at)
                        AssignedPersonsLine(persons: event.persons)
                        if let name = event.calendar_name {
                            Text(name)
                                .font(HomitaFont.inter(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    Spacer()
                    Text(Self.time(of: event.date_at))
                        .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkSoft)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var tasksCard: some View {
        let pages = store.pendingTaskPages
        let page = pages.first { $0.id == taskPageId } ?? pages.first
        return sectionCard(title: "Tareas pendientes", systemImage: "checklist",
                    count: store.tasks.filter { !$0.isCompleted }.count, destination: .tasks,
                    state: store.tasksState, retry: { await store.loadTasks() }) {
            if let page {
                // Puntos para cambiar de lista: entre el título y el contenido, sin animación.
                if pages.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(pages) { item in
                            Button {
                                var t = Transaction(); t.disablesAnimations = true
                                withTransaction(t) { taskPageId = item.id }
                            } label: {
                                Circle()
                                    .fill(item.id == page.id ? Palette.ink : Palette.inkMuted.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Lista \(item.name)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: page.colorHex)).frame(width: 10, height: 10)
                    Text(page.name)
                        .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkSoft)
                }
                // E1-03: máximo 5 pendientes por página; el resto se ve en «Ver más».
                ForEach(Array(page.tasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                    if index > 0 { Divider().overlay(Palette.line) }
                    HStack(spacing: 12) {
                        HomitaCheckbox(isOn: task.isCompleted, tintHex: Palette.onlineHex) {
                            Task { await store.toggleComplete(task) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                                .foregroundStyle(Palette.ink)
                            AssignedPersonsLine(persons: task.persons)
                        }
                        Spacer()
                    }
                }
                HStack {
                    Spacer()
                    Button("Ver más") { onOpen(.taskList(page.id)) }
                        .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.accent)
                }
            } else {
                emptyText(HomitaEmptyNoteText.pendingTasks)
            }
        }
    }

    private var routinesCard: some View {
        RoutinesTodayCard(store: store, dateText: dateText) { onOpen(.routines) }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCESOS RÁPIDOS")
                .font(HomitaFont.inter(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
            HStack(spacing: 12) {
                HomitaButton(title: "+ Tarea", kind: .secondary) {
                    Task {
                        await store.loadTaskLists()
                        if store.taskLists.isEmpty {
                            if store.errorMessage == nil { store.errorMessage = "Crea una lista de tareas primero" }
                        } else {
                            showTaskEditor = true
                        }
                    }
                }
                HomitaButton(title: "+ Evento") {
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
        title: String, systemImage: String, count: Int, destination: InicioDestination, state: InicioSectionState,
        retry: @escaping () async -> Void, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HomitaSectionHeader(title: title, count: state == .loaded ? count : nil, systemImage: systemImage)
                Button { onOpen(destination) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ir a \(title)")
            }
            Divider().overlay(Palette.line)
            switch state {
            case .idle, .loading:
                if count == 0 {
                    HomitaSkeletonRows(count: 2, height: 56, label: "Cargando")
                } else {
                    content()
                }
            case .failed(let message):
                Text(message)
                    .font(HomitaFont.inter(15, relativeTo: .body))
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
        HomitaEmptyNote(text: text)
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
