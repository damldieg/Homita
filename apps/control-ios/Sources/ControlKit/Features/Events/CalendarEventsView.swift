import SwiftUI

/// Pestaña Eventos: un día cada vez. Cabecera con flechas de semana y selector de fecha, tira de la semana
/// (con barras de los eventos de varios días) y lista del día. Solo eventos (las rutinas tienen su segmento).
/// Tocar un evento abre su detalle en push. El alta se hace desde el CTA «Nuevo evento» al final de la lista.
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
        // Un solo punto de alta: el CTA «Nuevo evento» al final de la lista (sin «+» en la barra superior).
        .errorAlert($calendarStore.errorMessage)
        // Un borrado que falla en el detalle (ya cerrado) se avisa aquí.
        .writeFailureToast($eventStore.writeFailure)
        // Al volver del detalle (guardar, eliminar o atrás) se recarga el rango visible.
        .onChange(of: selectedEvent?.id) { _, id in
            if id == nil { Task { await calendarStore.load() } }
        }
        .task {
            // «En curso» (D-020) se calcula en el store de agenda para el día elegido.
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
                    newEventButton
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Cabecera y navegación

    private var header: some View {
        HStack(spacing: 12) {
            // Las flechas mueven una semana y conservan el día de la semana.
            Button { Task { await calendarStore.moveWeek(-1) } } label: {
                Image(systemName: "chevron.left").foregroundStyle(Palette.ink)
            }
            .accessibilityLabel("Semana anterior")
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
            Button { Task { await calendarStore.moveWeek(1) } } label: {
                Image(systemName: "chevron.right").foregroundStyle(Palette.ink)
            }
            .accessibilityLabel("Semana siguiente")
        }
    }

    private var dayTitle: String {
        CalendarWeekLayout.dayTitle(calendarStore.anchor, timeZone: grid.timeZone)
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
            .environment(\.calendar, spanishCalendar)
            .environment(\.locale, CalendarWeekLayout.locale)
            .tint(Palette.accent)
            .padding(.horizontal)
            .navigationTitle("Elegir fecha")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

    /// Calendario de la rejilla con locale es_ES (selector de fecha).
    private var spanishCalendar: Calendar {
        var calendar = grid.calendar
        calendar.locale = CalendarWeekLayout.locale
        return calendar
    }

    private static let stripSpacing: CGFloat = 4
    private static let barHeight: CGFloat = 6
    private static let barSpacing: CGFloat = 3

    private var weekStrip: some View {
        let spans = CalendarWeekLayout.spans(events: calendarStore.events, weekDays: calendarStore.visibleDayStrings)
        return VStack(spacing: 8) {
            HStack(spacing: Self.stripSpacing) {
                ForEach(Array(CalendarWeekLayout.weekdayLetters().enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(HomitaFont.inter(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: Self.stripSpacing) {
                ForEach(calendarStore.visibleDays, id: \.self) { day in
                    dayCell(day)
                }
            }
            if !spans.isEmpty {
                multiDayBars(spans)
            }
        }
        .contentShape(Rectangle())
        // Deslizar la tira a los lados cambia de semana (solo gestos claramente horizontales).
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                guard let step = CalendarWeekLayout.weekStep(
                    swipeWidth: value.translation.width, height: value.translation.height
                ) else { return }
                Task { await calendarStore.moveWeek(step) }
            }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = grid.calendar
        let isSelected = calendar.isDate(day, inSameDayAs: calendarStore.anchor)
        let dayEvents = calendarStore.dayEvents(on: day)
        // Los puntos son solo para eventos de un día; los de varios días se ven como barra.
        let colors = Self.uniqueColors(calendarStore.listEvents(on: day))
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

    /// Barras continuas de los eventos de varios días, alineadas con las columnas de la tira y apiladas
    /// en filas cuando se solapan. Decorativas: la lista del día ya los nombra.
    private func multiDayBars(_ spans: [EventWeekSpan]) -> some View {
        let rows = CalendarWeekLayout.rowCount(spans)
        let height = CGFloat(rows) * Self.barHeight + CGFloat(max(rows - 1, 0)) * Self.barSpacing
        return GeometryReader { proxy in
            let column = (proxy.size.width - Self.stripSpacing * 6) / 7
            ForEach(spans, id: \.eventId) { span in
                let x = CGFloat(span.startColumn) * (column + Self.stripSpacing)
                let columns = CGFloat(span.endColumn - span.startColumn)
                let width = (columns + 1) * column + columns * Self.stripSpacing
                MultiDayBar(span: span)
                    .frame(width: width, height: Self.barHeight)
                    .offset(x: x, y: CGFloat(span.row) * (Self.barHeight + Self.barSpacing))
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Lista del día seleccionado

    /// Todo lo del día: los de varios días (cada día de su rango, con «Día N de M») y los que empiezan ese día.
    private var dayList: some View {
        let items = calendarStore.dayEvents(on: calendarStore.anchor)
        let day = calendarStore.dayString(calendarStore.anchor)
        return VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(
                title: dayTitle,
                count: items.count,
                systemImage: "calendar"
            )
            if items.isEmpty {
                CalendarFreeDayView()
            } else {
                ForEach(items, id: \.id) { event in
                    CalendarEventRow(event: event, dayLabel: CalendarWeekLayout.dayLabel(of: event, on: day)) {
                        selectedEvent = event
                    }
                }
            }
        }
    }

    /// CTA primario de alta al final de la lista, con o sin eventos.
    private var newEventButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text("Nuevo evento")
                    .font(HomitaFont.inter(17, weight: .semibold, relativeTo: .body))
            }
            .foregroundStyle(Palette.onFill)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.accent))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Auxiliares

    private static func format(_ template: String, _ date: Date, _ grid: CalendarGrid) -> String {
        let formatter = DateFormatter()
        formatter.calendar = grid.calendar
        formatter.timeZone = grid.timeZone
        formatter.locale = CalendarWeekLayout.locale
        // Plantilla de esqueleto: el formateador ordena y escribe las palabras en español.
        formatter.setLocalizedDateFormatFromTemplate(template)
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
        let date = format("dMMMM", day, grid)
        return count == 0 ? date : "\(date), \(count) \(count == 1 ? "evento" : "eventos")"
    }
}

/// Fila de evento en el calendario: barra de color, hora y título. Un evento de varios días lleva «Día N de M».
struct CalendarEventRow: View {
    let event: EventEntry
    var dayLabel: String? = nil
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HomitaCard {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: event.calendar_color ?? Palette.fallbackItem))
                        .frame(width: 5)
                    VStack(alignment: .leading, spacing: 4) {
                        if let dayLabel {
                            Text(dayLabel)
                                .font(HomitaFont.inter(12, weight: .semibold, relativeTo: .caption))
                                .foregroundStyle(Palette.accent)
                        }
                        Text(DateDisplay.dateTime(event.date_at).uppercased())
                            .font(HomitaFont.inter(12, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.inkSoft)
                        // Evento de varios días (0030): rango inicio → fin.
                        if let range = DateDisplay.eventRange(dateAt: event.date_at, endDate: event.end_date) {
                            Text(range)
                                .font(HomitaFont.inter(12, weight: .medium, relativeTo: .caption))
                                .foregroundStyle(Palette.inkSoft)
                        }
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

/// Barra de un evento de varios días en la tira: redondeada en los extremos; borde recto con flecha
/// en el lado por el que continúa en otra semana.
private struct MultiDayBar: View {
    let span: EventWeekSpan

    var body: some View {
        let radius: CGFloat = 3
        let color = Color(hex: span.colorHex)
        UnevenRoundedRectangle(
            topLeadingRadius: span.continuesBefore ? 0 : radius,
            bottomLeadingRadius: span.continuesBefore ? 0 : radius,
            bottomTrailingRadius: span.continuesAfter ? 0 : radius,
            topTrailingRadius: span.continuesAfter ? 0 : radius
        )
        .fill(color)
        .overlay(alignment: .leading) {
            if span.continuesBefore { arrow("chevron.left", color: color).offset(x: -9) }
        }
        .overlay(alignment: .trailing) {
            if span.continuesAfter { arrow("chevron.right", color: color).offset(x: 9) }
        }
    }

    private func arrow(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
    }
}

/// Estado vacío del día: ilustración cálida dibujada con formas (taza humeante bajo un sol),
/// título «Día libre» y una frase amable.
struct CalendarFreeDayView: View {
    var body: some View {
        VStack(spacing: 12) {
            illustration
            Text("Día libre")
                .font(HomitaFont.inter(18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Text("Nada agendado. Buen momento para descansar.")
                .font(HomitaFont.inter(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private var illustration: some View {
        ZStack {
            Circle()
                .fill(Palette.accentSoft)
                .frame(width: 120, height: 120)
            // Sol detrás de la taza.
            Circle()
                .fill(Palette.soon.opacity(0.85))
                .frame(width: 34, height: 34)
                .offset(x: 30, y: -30)
            // Vapor.
            ForEach(0..<2, id: \.self) { index in
                SteamCurve()
                    .stroke(Palette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 10, height: 24)
                    .offset(x: CGFloat(index) * 14 - 13, y: -24)
            }
            // Taza.
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                .fill(Palette.accent)
                .frame(width: 50, height: 38)
                .offset(x: -6, y: 14)
            Circle()
                .stroke(Palette.accent, lineWidth: 5)
                .frame(width: 18, height: 18)
                .offset(x: 22, y: 12)
            // Platillo.
            Capsule()
                .fill(Palette.accentPress.opacity(0.35))
                .frame(width: 72, height: 7)
                .offset(x: -4, y: 36)
        }
        .frame(width: 120, height: 120)
        .accessibilityHidden(true)
    }
}

/// Curva en S del vapor de la taza.
private struct SteamCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX - rect.width * 0.4, y: rect.maxY - rect.height * 0.35),
            control2: CGPoint(x: rect.maxX + rect.width * 0.4, y: rect.minY + rect.height * 0.35)
        )
        return path
    }
}
