import SwiftUI

/// Pestaña Eventos: un día cada vez. Cabecera con flechas y selector de fecha, tira de la semana y lista del día.
/// Solo eventos (las rutinas tienen su segmento). Tocar un evento abre su detalle en push.
struct CalendarEventsView: View {
    @Bindable var eventStore: EventStore
    @Bindable var calendarStore: CalendarAgendaStore
    let calendars: CalendarStore
    let persons: PersonStore

    @State private var selectedEvent: EventEntry?
    @State private var showCreate = false
    @State private var showPicker = false

    private var grid: CalendarGrid { calendarStore.grid }

    var body: some View {
        VStack(spacing: 0) {
            calendarContent
        }
        .sheet(isPresented: $showPicker) { datePickerSheet }
        .navigationDestination(isPresented: detailPresented) {
            if let event = selectedEvent {
                EventDetailView(store: eventStore, calendars: calendars, persons: persons, event: event)
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            // El alta no pasa por el detalle push: al cerrar la hoja se recarga el rango (R1-02).
            Task { await calendarStore.load() }
        }) {
            NavigationStack {
                EventDetailView(store: eventStore, calendars: calendars, persons: persons, event: nil,
                                defaultDate: newEventDate)
            }
        }
        .toolbar {
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
        .errorAlert($calendarStore.errorMessage)
        // Un borrado que falla en el detalle (ya cerrado) se avisa aquí.
        .writeFailureToast($eventStore.writeFailure)
        // Al volver del detalle (guardar, eliminar o atrás) se recarga el rango visible.
        .onChange(of: selectedEvent?.id) { _, id in
            if id == nil { Task { await calendarStore.load() } }
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

    private var detailPresented: Binding<Bool> {
        Binding(get: { selectedEvent != nil }, set: { if !$0 { selectedEvent = nil } })
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !calendarStore.hasLoaded {
                    HomitaSkeletonRows(count: 3, height: 64, label: "Cargando calendario")
                } else {
                    weekStrip
                    dayList
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        // Deslizar a los lados cambia de día (solo gestos claramente horizontales).
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                Task { await calendarStore.move(dx < 0 ? 1 : -1) }
            }
        )
    }

    // MARK: - Cabecera y navegación

    private var header: some View {
        HStack(spacing: 12) {
            Button { Task { await calendarStore.move(-1) } } label: {
                Image(systemName: "chevron.left").foregroundStyle(Palette.ink)
            }
            .accessibilityLabel("Día anterior")
            Button { showPicker = true } label: {
                HStack(spacing: 6) {
                    Text(dayTitle)
                        .font(HomitaFont.inter(18, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(dayTitle). Elegir fecha")
            if !calendarStore.isToday {
                Button("Hoy") { Task { await calendarStore.goToToday() } }
                    .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.accent)
            }
            Button { Task { await calendarStore.move(1) } } label: {
                Image(systemName: "chevron.right").foregroundStyle(Palette.ink)
            }
            .accessibilityLabel("Día siguiente")
        }
    }

    private var dayTitle: String {
        Self.format("EEEEdMMMM", calendarStore.anchor, grid).capitalized
    }

    /// Hoja con el selector gráfico: permite saltar a cualquier día sin pasar por los intermedios.
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Fecha",
                selection: Binding(
                    get: { calendarStore.anchor },
                    set: { date in Task { await calendarStore.select(date) } }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.calendar, grid.calendar)
            .tint(Palette.accent)
            .padding(.horizontal)
            .navigationTitle("Elegir fecha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hoy") {
                        Task { await calendarStore.goToToday() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { showPicker = false }
                }
            }
            .background(Palette.background.ignoresSafeArea())
        }
        .presentationDetents([.medium])
    }

    // MARK: - Tira de la semana

    private var weekStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(Self.weekdayLetters(grid).enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(HomitaFont.inter(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 4) {
                ForEach(calendarStore.visibleDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = grid.calendar
        let isSelected = calendar.isDate(day, inSameDayAs: calendarStore.anchor)
        let dayEvents = calendarStore.events(on: day)
        let colors = Self.uniqueColors(dayEvents)
        let number = calendar.component(.day, from: day)

        return Button {
            Task { await calendarStore.select(day) }
        } label: {
            VStack(spacing: 4) {
                Text("\(number)")
                    .font(HomitaFont.inter(15, weight: isSelected ? .bold : .medium, relativeTo: .body))
                    .foregroundStyle(isSelected ? Palette.onFill : Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isSelected ? Palette.accent : Color.clear))
                HStack(spacing: 2) {
                    ForEach(Array(colors.prefix(3)), id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
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
                title: dayTitle,
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
        formatter.locale = grid.calendar.locale
        // Plantilla de esqueleto: el sistema localiza el orden y las palabras (A6).
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Letras de los días en el idioma del dispositivo, empezando por el lunes (A6).
    static func weekdayLetters(_ grid: CalendarGrid) -> [String] {
        let symbols = grid.calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return ["L", "M", "X", "J", "V", "S", "D"] }
        // veryShort… empieza en domingo (índice 0); se rota para que la semana empiece en lunes.
        return Array(symbols[1...]) + [symbols[0]]
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
        let date = format("dMMMM", day, grid)
        return count == 0 ? date : "\(date), \(count) \(count == 1 ? "evento" : "eventos")"
    }
}

/// Fila de evento en el calendario: barra de color, hora y título.
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
                            .font(HomitaFont.inter(12, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.inkSoft)
                        Text(event.title)
                            .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                        EventCountdownLabel(dateAt: event.date_at)
                        AssignedPersonsLine(persons: event.persons)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
