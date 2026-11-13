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

    public init(services: AppServices, segment: Binding<Int>) {
        self.services = services
        _segment = segment
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
                // En paralelo: antes iban una tras otra y retrasaban el primer pintado. La agenda de
                // Eventos carga su propia semana; `eventStore` solo se usa para guardar y borrar.
                async let calendars: Void = calendarStore.load()
                async let persons: Void = personStore.load()
                async let routines: Void = routineStore.load()
                _ = await (calendars, persons, routines)
            }
        }
    }
}
