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

    init(store: EventStore, calendars: CalendarStore, persons: PersonStore, event: EventEntry?) {
        self.store = store
        self.calendars = calendars
        self.persons = persons
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _date = State(initialValue: event.flatMap { PHPDateTime.parse($0.date_at) } ?? Date())
        _calendarId = State(initialValue: event?.calendar_id ?? calendars.calendars.first?.id ?? 0)
        _alarm = State(initialValue: event?.alarm)
        _personIds = State(initialValue: event?.persons?.map(\.id) ?? [])
    }

    var body: some View {
        Form {
            Section("Evento") {
                TextField("Título", text: $title)
                DatePicker("Fecha y hora", selection: $date)
                if event == nil {
                    Picker("Calendario", selection: $calendarId) {
                        ForEach(calendars.calendars, id: \.id) { calendar in
                            Text(calendar.name).tag(calendar.id)
                        }
                    }
                }
            }
            Section {
                AlarmField(alarm: $alarm)
            }
            PersonSelector(persons: persons.persons, selected: $personIds)
            Section {
                Button(event == nil ? "Crear evento" : "Guardar") {
                    Task { await save() }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            if event != nil {
                Section {
                    Button("Eliminar evento", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(event == nil ? "Nuevo evento" : "Editar evento")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
        .confirmationDialog(
            "Se eliminará el evento.",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Eliminar evento", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancelar", role: .cancel) {}
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
