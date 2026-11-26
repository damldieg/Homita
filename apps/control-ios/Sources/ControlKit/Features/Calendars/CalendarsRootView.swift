import SwiftUI

/// Pestaña Calendario: segmento "Eventos" / "Rutinas" / "Calendarios" sobre un único
/// `NavigationStack` (paridad con la gestora Android).
public struct CalendarsRootView: View {
    let services: AppServices
    @State private var calendarStore: CalendarStore
    @State private var eventStore: EventStore
    @State private var calendarAgenda: CalendarAgendaStore
    @State private var routineStore: RoutineStore
    @State private var personStore: PersonStore
    @Binding private var segment: Int
    /// Último cambio de Kito visto por cada grupo de almacenes (ver `KitoReloadTargets`).
    @State private var agendaGate: KitoReloadGate
    @State private var calendarsGate: KitoReloadGate
    @State private var routinesGate: KitoReloadGate

    public init(services: AppServices, segment: Binding<Int>) {
        self.services = services
        _segment = segment
        let changes = services.kitoChanges
        _agendaGate = State(initialValue: KitoReloadGate(seen: changes.counter(for: KitoReloadTargets.agenda)))
        _calendarsGate = State(initialValue: KitoReloadGate(seen: changes.counter(for: KitoReloadTargets.calendars)))
        _routinesGate = State(initialValue: KitoReloadGate(seen: changes.counter(for: KitoReloadTargets.routines)))
        _calendarStore = State(initialValue: CalendarStore(repo: services.calendars, events: services.events, routines: services.routines, persons: services.persons))
        _eventStore = State(initialValue: EventStore(repo: services.events))
        _calendarAgenda = State(initialValue: CalendarAgendaStore(repo: services.events))
        _routineStore = State(initialValue: RoutineStore(repo: services.routines, events: services.events))
        _personStore = State(initialValue: PersonStore(repo: services.persons))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HomitaSegmented(selection: $segment, items: [
                    (id: 0, title: "Eventos"), (id: 1, title: "Rutinas"), (id: 2, title: "Calendarios"),
                ])
                .padding([.horizontal, .top])

                switch segment {
                case 0:
                    CalendarEventsView(eventStore: eventStore, calendarStore: calendarAgenda, calendars: calendarStore, persons: personStore)
                case 1:
                    RoutineListView(store: routineStore, calendars: calendarStore, persons: personStore)
                default:
                    CalendarListView(store: calendarStore)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(["Eventos", "Rutinas", "Calendarios"][segment])
            .task {
                // En paralelo: antes iban una tras otra y retrasaban el primer pintado. La agenda de
                // Eventos carga su propia semana; `eventStore` solo se usa para guardar y borrar.
                async let calendars: Void = calendarStore.load()
                async let persons: Void = personStore.load()
                async let routines: Void = routineStore.load()
                _ = await (calendars, persons, routines)
            }
            // Cambios de Kito: se recarga solo lo afectado, en el acto si la pestaña está montada o al volver a ella.
            .onChange(of: services.kitoChanges.counter(for: KitoReloadTargets.agenda)) { _, _ in reloadFromKito() }
            .onChange(of: services.kitoChanges.counter(for: KitoReloadTargets.calendars)) { _, _ in reloadFromKito() }
            .onChange(of: services.kitoChanges.counter(for: KitoReloadTargets.routines)) { _, _ in reloadFromKito() }
            .onAppear { reloadFromKito() }
        }
    }

    /// Recarga lo que haya cambiado Kito desde la última vez (cada grupo una sola vez).
    private func reloadFromKito() {
        let changes = services.kitoChanges
        if calendarsGate.shouldReload(current: changes.counter(for: KitoReloadTargets.calendars)) {
            Task { await calendarStore.load() }
        }
        if agendaGate.shouldReload(current: changes.counter(for: KitoReloadTargets.agenda)) {
            Task {
                await calendarAgenda.load()
                await eventStore.load()
            }
        }
        if routinesGate.shouldReload(current: changes.counter(for: KitoReloadTargets.routines)) {
            Task { await routineStore.load() }
        }
    }
}
