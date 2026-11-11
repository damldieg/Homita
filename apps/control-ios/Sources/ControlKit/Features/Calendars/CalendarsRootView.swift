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
    @State private var segment = 0

    public init(services: AppServices) {
        self.services = services
        _calendarStore = State(initialValue: CalendarStore(repo: services.calendars, events: services.events, routines: services.routines))
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
                await calendarStore.load()
                await personStore.load()
                await eventStore.load()
                await routineStore.load()
            }
        }
    }
}
