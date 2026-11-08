import SwiftUI

/// Pestaña Calendario: segmento "Eventos" / "Rutinas" / "Calendarios" sobre un único
/// `NavigationStack` (paridad con la gestora Android).
public struct CalendarsRootView: View {
    let services: AppServices
    @State private var calendarStore: CalendarStore
    @State private var eventStore: EventStore
    @State private var routineStore: RoutineStore
    @State private var personStore: PersonStore
    @State private var segment = 0

    public init(services: AppServices) {
        self.services = services
        _calendarStore = State(initialValue: CalendarStore(repo: services.calendars))
        _eventStore = State(initialValue: EventStore(repo: services.events))
        _routineStore = State(initialValue: RoutineStore(repo: services.routines, events: services.events))
        _personStore = State(initialValue: PersonStore(repo: services.persons))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("Eventos").tag(0)
                    Text("Rutinas").tag(1)
                    Text("Calendarios").tag(2)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                switch segment {
                case 0:
                    EventListView(store: eventStore, calendars: calendarStore, persons: personStore)
                case 1:
                    RoutineListView(store: routineStore, calendars: calendarStore, persons: personStore)
                default:
                    CalendarListView(store: calendarStore)
                }
            }
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
