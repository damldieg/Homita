import SwiftUI

/// Editor de rutina (alta/edición): frecuencia (diaria/semanal/mensual), intervalo, días ISO,
/// inicio/fin, activa/pausa, aviso y personas. `RoutineRule` valida el formulario antes de
/// guardar (mismas reglas que `Routine.php`); el aviso se guarda en el servidor pero el iPhone
/// no avisa en v1.
struct RoutineEditorView: View {
    @Bindable var store: RoutineStore
    let calendars: CalendarStore
    let persons: PersonStore
    let routine: RoutineEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var calendarId: Int
    @State private var frequency: String
    @State private var interval: Int
    @State private var days: Set<Int>
    @State private var time: Date
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var active: Bool
    @State private var alarm: Int?
    @State private var personIds: [Int]
    @State private var showDeleteConfirm = false
    @State private var isWorking = false

    /// ISO 8601 (1 = lunes), letra visible y nombre completo para VoiceOver (I5).
    private static let weekdayLabels = [
        (1, "L", "lunes"), (2, "M", "martes"), (3, "X", "miércoles"), (4, "J", "jueves"),
        (5, "V", "viernes"), (6, "S", "sábado"), (7, "D", "domingo"),
    ]

    init(store: RoutineStore, calendars: CalendarStore, persons: PersonStore, routine: RoutineEntry?) {
        self.store = store
        self.calendars = calendars
        self.persons = persons
        self.routine = routine
        _title = State(initialValue: routine?.title ?? "")
        _calendarId = State(initialValue: routine?.calendar_id ?? calendars.calendars.first?.id ?? 0)
        _frequency = State(initialValue: routine?.frequency ?? "daily")
        _interval = State(initialValue: routine?.intervalValue ?? 1)
        _days = State(initialValue: Set(routine?.weekdays ?? []))
        _time = State(initialValue: routine.flatMap { Self.parseTime($0.time) } ?? Self.parseTime("09:00") ?? Date())
        _startDate = State(initialValue: routine.flatMap { PHPDateTime.parseDay($0.start_date) } ?? Date())
        _hasEndDate = State(initialValue: routine?.end_date != nil)
        _endDate = State(initialValue: routine?.end_date.flatMap { PHPDateTime.parseDay($0) } ?? Date())
        _active = State(initialValue: routine?.isActive ?? true)
        _alarm = State(initialValue: routine?.alarm)
        _personIds = State(initialValue: routine?.persons?.map(\.id) ?? [])
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Rutina", systemImage: "repeat") {
                HomitaField(placeholder: "Título", text: $title)
                if routine == nil {
                    Text("Calendario")
                        .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                    HomitaRadioGroup(
                        selection: Binding(get: { calendarId }, set: { calendarId = $0 ?? calendarId }),
                        items: calendars.calendars.map { (id: $0.id, title: $0.name) }
                    )
                }
            }
            HomitaPanel("Frecuencia", systemImage: "calendar.day.timeline.left") {
                HomitaRadioGroup(
                    selection: Binding(get: { frequency }, set: { frequency = $0 ?? frequency }),
                    items: [(id: "daily", title: "Diaria"), (id: "weekly", title: "Semanal"), (id: "monthly", title: "Mensual")]
                )
                // El Stepper no tiene equivalente en ComponentsKit: se mantiene nativo.
                Stepper("Cada \(interval) \(unitLabel)", value: $interval, in: 1...99)
                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                // E3-06 [Nuevo]: resumen en lenguaje natural de la regla.
                Text(RoutineSummary.text(frequency: frequency, interval: interval, days: Array(days), hour: hourText))
                    .font(HomitaFont.inter(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
                    .accessibilityLabel("Resumen: " + RoutineSummary.text(frequency: frequency, interval: interval, days: Array(days), hour: hourText))
                if frequency == "weekly" {
                    // Selección múltiple de días: ComponentsKit solo ofrece selección única.
                    HStack(spacing: 6) {
                        ForEach(Self.weekdayLabels, id: \.0) { iso, label, name in
                            Button {
                                if days.contains(iso) { days.remove(iso) } else { days.insert(iso) }
                            } label: {
                                Text(label)
                                    .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(days.contains(iso) ? Palette.onFill : Palette.ink)
                                    .frame(width: 38, height: 38)
                                    .background(days.contains(iso) ? Palette.accent : Palette.background, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                }
            }
            HomitaPanel("Horario", systemImage: "clock") {
                HomitaDatePicker(title: "Hora", selection: $time, components: .hourAndMinute)
                HomitaDatePicker(title: "Inicio", selection: $startDate, components: .date)
                HomitaToggle(title: "Fecha fin", isOn: $hasEndDate)
                if hasEndDate {
                    HomitaDatePicker(title: "Fin", selection: $endDate, components: .date)
                }
            }
            HomitaPanel("Estado", systemImage: "power") {
                HomitaToggle(title: "Activa", isOn: $active)
            }
            AlarmField(alarm: $alarm)
            PersonSelector(persons: persons.persons, selected: $personIds)
            HomitaButton(
                title: routine == nil ? "Crear rutina" : "Guardar",
                isEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking,
                isLoading: isWorking
            ) {
                Task { await save() }
            }
            if routine != nil {
                HomitaButton(title: "Eliminar rutina", kind: .secondary) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle(routine == nil ? "Nueva rutina" : "Editar rutina")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
        .homitaConfirm("Se eliminará la rutina y sus sesiones futuras.", isPresented: $showDeleteConfirm, confirmTitle: "Eliminar rutina") {
            Task { await delete() }
        }
        .errorAlert($store.errorMessage)
        // «Reintentar» que va bien cierra el editor, igual que un guardado correcto.
        .writeFailureToast($store.writeFailure) { dismiss() }
    }

    /// Hora del editor como «HH:mm».
    private var hourText: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private var unitLabel: String {
        switch frequency {
        case "weekly": return interval == 1 ? "semana" : "semanas"
        case "monthly": return interval == 1 ? "mes" : "meses"
        default: return interval == 1 ? "día" : "días"
        }
    }

    /// `HH:mm` del contrato ↔ `Date` (solo hora).
    private static func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private static func parseTime(_ string: String) -> Date? {
        timeFormatter().date(from: string)
    }

    private func timeString() -> String {
        Self.timeFormatter().string(from: time)
    }

    private func save() async {
        let sortedDays = days.sorted()
        guard let rule = RoutineRule.Frequency(rawValue: frequency),
              (try? RoutineRule(
                frequency: rule,
                interval: interval,
                days: sortedDays,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil
              )) != nil else {
            store.errorMessage = "Revisa la frecuencia, el intervalo, los días y el rango de fechas"
            return
        }
        isWorking = true
        defer { isWorking = false }
        let draft = RoutineDraft(
            calendarId: calendarId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            frequency: frequency,
            interval: interval,
            days: frequency == "weekly" ? sortedDays : [],
            time: timeString(),
            startDate: PHPDateTime.formatDay(startDate),
            endDate: hasEndDate ? PHPDateTime.formatDay(endDate) : nil,
            active: active,
            alarm: alarm,
            personIds: personIds
        )
        let ok = await store.save(draft: draft, editing: routine)
        if ok { dismiss() }
    }

    private func delete() async {
        guard let routine else { return }
        isWorking = true
        defer { isWorking = false }
        await store.delete(routine)
        dismiss()
    }
}
