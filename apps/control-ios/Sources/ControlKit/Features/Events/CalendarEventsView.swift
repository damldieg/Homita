import SwiftUI

/// Pestaña Eventos (B3): conmutador Mes / Semana / Día / Agenda. «Agenda» es la lista de
/// Próximos y Pasados con búsqueda (`EventListView`). Tocar un evento abre su detalle en push.
struct CalendarEventsView: View {
    @Bindable var eventStore: EventStore
    @Bindable var calendarStore: CalendarAgendaStore
    let calendars: CalendarStore
    let persons: PersonStore

    @State private var selectedEvent: EventEntry?
    @State private var showCreate = false

    private var grid: CalendarGrid { calendarStore.grid }

    var body: some View {
        VStack(spacing: 0) {
            HomitaSegmented(
                selection: Binding(get: { calendarStore.mode }, set: changeMode),
                items: CalendarMode.allCases.map { (id: $0, title: $0.title) }
            )
            .padding([.horizontal, .top])

            if calendarStore.mode == .agenda {
                EventListView(store: eventStore, calendars: calendars, persons: persons)
            } else {
                calendarContent
            }
        }
        .navigationDestination(isPresented: detailPresented) {
            if let event = selectedEvent {
                EventDetailView(store: eventStore, calendars: calendars, persons: persons, event: event)
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            // El alta no pasa por el detalle push: al cerrar la hoja se recarga el rango (R1-02).
            if calendarStore.mode != .agenda { Task { await calendarStore.load() } }
        }) {
            NavigationStack {
                EventDetailView(store: eventStore, calendars: calendars, persons: persons, event: nil,
                                defaultDate: newEventDate)
            }
        }
        .toolbar {
            if calendarStore.mode != .agenda {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Palette.ink)
                            .accessibilityLabel("Nuevo evento")
                    }
                }
            }
        }
        .errorAlert($calendarStore.errorMessage)
        // Al volver del detalle (guardar, eliminar o atrás) se recarga el rango visible.
        .onChange(of: selectedEvent?.id) { _, id in
            if id == nil, calendarStore.mode != .agenda {
                Task { await calendarStore.load() }
            }
        }
        .task {
            if !calendarStore.hasLoaded { await calendarStore.load() }
        }
    }

    /// Alta: día seleccionado a la hora actual (no a las 00:00 del día) (N2-01).
    private var newEventDate: Date {
        let calendar = grid.calendar
        let hour = calendar.component(.hour, from: Date())
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendarStore.anchor) ?? calendarStore.anchor
    }

    private func changeMode(_ mode: CalendarMode) {
        Task { await calendarStore.setMode(mode) }
    }

    private var detailPresented: Binding<Bool> {
        Binding(get: { selectedEvent != nil }, set: { if !$0 { selectedEvent = nil } })
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !calendarStore.hasLoaded {
                    HomitaLoadingCard(message: "Cargando calendario…")
                } else {
                    dayGrid
                    dayList
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Cabecera y navegación

    private var header: some View {
        HStack(spacing: 12) {
            Button { Task { await calendarStore.move(-1) } } label: {
                Image(systemName: "chevron.left").foregroundStyle(Palette.ink)
            }
            .accessibilityLabel(calendarStore.mode == .month ? "Mes anterior" : "Anterior")
            Text(rangeTitle)
                .font(HomitaFont.geist(18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
            Button { Task { await calendarStore.move(1) } } label: {
                Image(systemName: "chevron.right").foregroundStyle(Palette.ink)
            }
            .accessibilityLabel(calendarStore.mode == .month ? "Mes siguiente" : "Siguiente")
        }
    }

    private var rangeTitle: String {
        let anchor = calendarStore.anchor
        switch calendarStore.mode {
        case .month:
            return Self.format("LLLL yyyy", anchor, grid).capitalized
        case .week:
            let days = calendarStore.visibleDays
            guard let first = days.first, let last = days.last else { return "" }
            return "\(Self.format("d MMM", first, grid)) – \(Self.format("d MMM", last, grid))"
        case .day, .agenda:
            return Self.format("EEEE d 'de' MMMM", anchor, grid).capitalized
        }
    }

    // MARK: - Cuadrícula

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { letter in
                    Text(letter)
                        .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(calendarStore.visibleDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = grid.calendar
        let isSelected = calendar.isDate(day, inSameDayAs: calendarStore.anchor)
        let inMonth = calendarStore.mode != .month || calendar.isDate(day, equalTo: calendarStore.anchor, toGranularity: .month)
        let dayEvents = calendarStore.events(on: day)
        let colors = Self.uniqueColors(dayEvents)
        let number = calendar.component(.day, from: day)

        return Button {
            Task { await calendarStore.select(day) }
        } label: {
            VStack(spacing: 4) {
                Text("\(number)")
                    .font(HomitaFont.geist(15, weight: isSelected ? .bold : .medium, relativeTo: .body))
                    .foregroundStyle(isSelected ? Palette.card : (inMonth ? Palette.ink : Palette.inkMuted))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isSelected ? Palette.accent : Color.clear))
                HStack(spacing: 2) {
                    ForEach(Array(colors.prefix(3)), id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(day: day, count: dayEvents.count, grid: grid))
    }

    // MARK: - Lista del día seleccionado

    private var dayList: some View {
        let items = calendarStore.events(on: calendarStore.anchor)
        return VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(
                title: Self.format("EEEE d 'de' MMMM", calendarStore.anchor, grid).capitalized,
                count: items.count,
                systemImage: "calendar"
            )
            if items.isEmpty {
                HomitaFootnote(text: "Sin eventos este día.")
                HomitaButton(title: "Nuevo evento", kind: .secondary) { showCreate = true }
            } else {
                ForEach(items, id: \.id) { event in
                    CalendarEventRow(event: event) { selectedEvent = event }
                }
            }
        }
    }

    // MARK: - Auxiliares

    private static func format(_ template: String, _ date: Date, _ grid: CalendarGrid) -> String {
        let formatter = DateFormatter()
        formatter.calendar = grid.calendar
        formatter.timeZone = grid.timeZone
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = template
        return formatter.string(from: date)
    }

    private static func uniqueColors(_ events: [EventEntry]) -> [String] {
        var seen: [String] = []
        for event in events {
            let hex = event.calendar_color ?? Palette.fallbackItem
            if !seen.contains(hex) { seen.append(hex) }
        }
        return seen
    }

    private static func accessibilityLabel(day: Date, count: Int, grid: CalendarGrid) -> String {
        let date = format("d 'de' MMMM", day, grid)
        return count == 0 ? date : "\(date), \(count) \(count == 1 ? "evento" : "eventos")"
    }
}

/// Fila de evento en el calendario: barra de color, hora, título y marca de sesión de rutina.
struct CalendarEventRow: View {
    let event: EventEntry
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HomitaCard {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: event.calendar_color ?? Palette.fallbackItem))
                        .frame(width: 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateDisplay.dateTime(event.date_at).uppercased())
                            .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.inkSoft)
                        Text(event.title)
                            .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                        if event.routine_id != nil {
                            Text("Sesión de rutina")
                                .font(HomitaFont.geist(12, relativeTo: .caption))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
