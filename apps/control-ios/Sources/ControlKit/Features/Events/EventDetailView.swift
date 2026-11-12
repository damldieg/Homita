import SwiftUI

/// Editor de evento (alta/edición): título, fecha/hora, alarma y personas asignadas. v1 sin
/// "modo IA": título y fecha son obligatorios (`EventValidation`). Si es sesión de rutina, el
/// servidor guarda la excepción de título/fecha (`routine_exception`).
struct EventDetailView: View {
    @Bindable var store: EventStore
    let calendars: CalendarStore
    let persons: PersonStore
    let event: EventEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var calendarId: Int
    @State private var alarm: Int?
    @State private var personIds: [Int]
    @State private var showDeleteConfirm = false
    @State private var isWorking = false

    init(store: EventStore, calendars: CalendarStore, persons: PersonStore, event: EventEntry?, defaultDate: Date? = nil) {
        self.store = store
        self.calendars = calendars
        self.persons = persons
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _date = State(initialValue: event.flatMap { PHPDateTime.parse($0.date_at) } ?? defaultDate ?? Date())
        _calendarId = State(initialValue: event?.calendar_id ?? calendars.calendars.first?.id ?? 0)
        _alarm = State(initialValue: event?.alarm)
        _personIds = State(initialValue: event?.persons?.map(\.id) ?? [])
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Evento", systemImage: "calendar") {
                HomitaField(placeholder: "Título", text: $title)
                HomitaDatePicker(title: "Fecha y hora", selection: $date, components: [.date, .hourAndMinute])
                Group {
                    Text("Calendario")
                        .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                    if event == nil {
                        HomitaRadioGroup(
                            selection: Binding(get: { calendarId }, set: { calendarId = $0 ?? calendarId }),
                            items: calendars.calendars.map { (id: $0.id, title: $0.name) }
                        )
                    } else {
                        // Editar: el calendario del evento se muestra, no se cambia (R1-05 / CA-4).
                        Text(event?.calendar_name ?? "Calendario")
                            .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            AlarmField(alarm: $alarm)
            PersonSelector(persons: persons.persons, selected: $personIds)
            HomitaButton(
                title: event == nil ? "Crear evento" : "Guardar",
                isEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking,
                isLoading: isWorking
            ) {
                Task { await save() }
            }
            if event != nil {
                HomitaButton(title: "Eliminar evento", kind: .secondary) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle(event == nil ? "Nuevo evento" : "Editar evento")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
        .homitaConfirm(event?.routine_id != nil ? "Solo se cancelará esta sesión de la rutina." : "Se eliminará el evento.", isPresented: $showDeleteConfirm, confirmTitle: "Eliminar evento") {
            Task { await delete() }
        }
        .errorAlert($store.errorMessage)
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        let draft = EventDraft(
            calendarId: calendarId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dateAt: PHPDateTime.format(date),
            alarm: alarm,
            personIds: personIds
        )
        let ok = await store.save(draft: draft, editing: event)
        if ok { dismiss() }
    }

    private func delete() async {
        guard let event else { return }
        isWorking = true
        defer { isWorking = false }
        await store.delete(event)
        dismiss()
    }
}
