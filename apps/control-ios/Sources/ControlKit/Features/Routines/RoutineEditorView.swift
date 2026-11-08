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

    private static let weekdayLabels = [(1, "L"), (2, "M"), (3, "X"), (4, "J"), (5, "V"), (6, "S"), (7, "D")]

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
        Form {
            Section("Rutina") {
                TextField("Título", text: $title)
                if routine == nil {
                    Picker("Calendario", selection: $calendarId) {
                        ForEach(calendars.calendars, id: \.id) { calendar in
                            Text(calendar.name).tag(calendar.id)
                        }
                    }
                }
            }
            Section("Frecuencia") {
                Picker("Repetir", selection: $frequency) {
                    Text("Diaria").tag("daily")
                    Text("Semanal").tag("weekly")
                    Text("Mensual").tag("monthly")
                }
                Stepper("Cada \(interval) \(unitLabel)", value: $interval, in: 1...99)
                if frequency == "weekly" {
                    HStack {
                        ForEach(Self.weekdayLabels, id: \.0) { iso, label in
                            Button(label) {
                                if days.contains(iso) { days.remove(iso) } else { days.insert(iso) }
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(days.contains(iso) ? Color.white : Color.primary)
                            .background(days.contains(iso) ? Color.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            Section("Horario") {
                DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                DatePicker("Inicio", selection: $startDate, displayedComponents: .date)
                Toggle("Fecha fin", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                }
            }
            Section("Estado") {
                Toggle("Activa", isOn: $active)
            }
            Section {
                AlarmField(alarm: $alarm)
            }
            PersonSelector(persons: persons.persons, selected: $personIds)
            Section {
                Button(routine == nil ? "Crear rutina" : "Guardar") {
                    Task { await save() }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            if routine != nil {
                Section {
                    Button("Eliminar rutina", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(routine == nil ? "Nueva rutina" : "Editar rutina")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
        .confirmationDialog(
            "Se eliminará la rutina y sus sesiones futuras.",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Eliminar rutina", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .errorAlert($store.errorMessage)
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
