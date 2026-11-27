import SwiftUI

/// Sección «Pantallas» de Hogar (dashboard-pantalla-hogar): las pantallas del hogar, vincular una con el código que
/// muestra y ajustar cada una (horario, brillo, calendarios y listas). La ubicación del tiempo es la del hogar.
struct DisplaysCard: View {
    let store: DisplaysStore
    let canManage: Bool
    let calendars: [CalendarEntry]
    let taskLists: [TaskListEntry]
    @State private var linking = false
    @State private var editing: HomeDisplay?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(title: "Pantallas", count: store.state == .loaded ? store.displays.count : nil, systemImage: "rectangle.on.rectangle")
            switch store.state {
            case .idle, .loading:
                HomitaSkeletonRows(count: 1, height: 52, label: "Cargando pantallas")
            case .failed(let message):
                Text(message).font(HomitaFont.inter(15, relativeTo: .body)).foregroundStyle(Palette.accent)
                HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.load() } }
            case .loaded:
                if store.displays.isEmpty {
                    Text("Ninguna pantalla vinculada. Enciende el marco y escribe el código que muestra.")
                        .font(HomitaFont.inter(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkMuted)
                }
                ForEach(store.displays) { display in
                    Button { editing = display } label: { row(display) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ajustes de la pantalla")
                }
            }
            if canManage {
                HomitaButton(title: "Vincular pantalla", kind: .accentOutline) { linking = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
        .sheet(isPresented: $linking) {
            NavigationStack { LinkDisplaySheet(store: store) }
        }
        .sheet(item: $editing) { display in
            NavigationStack {
                DisplayDetailSheet(store: store, display: display, canManage: canManage, calendars: calendars, taskLists: taskLists)
            }
        }
    }

    private func row(_ display: HomeDisplay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .background(Palette.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(display.name).font(HomitaFont.inter(17, weight: .semibold, relativeTo: .body)).foregroundStyle(Palette.ink)
                Text(display.lastSeenAt.map { "Última conexión \($0.prefix(16))" } ?? "Sin conexiones todavía")
                    .font(HomitaFont.inter(14, relativeTo: .footnote)).foregroundStyle(Palette.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Palette.inkMuted).accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Vincular: la pantalla muestra un código de 6 dígitos; se escribe aquí junto con el nombre que tendrá.
struct LinkDisplaySheet: View {
    let store: DisplaysStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Escribe el código que aparece en la pantalla. Caduca en 10 minutos.")
                    .font(HomitaFont.inter(16, relativeTo: .body)).foregroundStyle(Palette.inkMuted)
                HomitaField(placeholder: "Código de 6 dígitos", text: $code, isCode: true)
                HomitaField(placeholder: "Nombre (p. ej. Salón)", text: $name)
                if let error = store.lastError {
                    Text(error).font(HomitaFont.inter(15, relativeTo: .body)).foregroundStyle(Palette.accent)
                }
                HomitaButton(title: working ? "Vinculando…" : "Vincular", kind: .primary,
                             isEnabled: code.filter(\.isNumber).count == 6 && !name.trimmingCharacters(in: .whitespaces).isEmpty && !working) {
                    Task {
                        working = true
                        let linked = await store.link(code: code, name: name)
                        working = false
                        if linked { dismiss() }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Vincular pantalla")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
    }
}

/// Ajustes de una pantalla: nombre, brillo, horario, calendarios y listas que enseña, y revocarla.
struct DisplayDetailSheet: View {
    let store: DisplaysStore
    let display: HomeDisplay
    let canManage: Bool
    let calendars: [CalendarEntry]
    let taskLists: [TaskListEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var automaticBrightness: Bool
    @State private var brightness: Double
    @State private var schedule: DisplaySchedule
    @State private var scheduleOn: Bool
    @State private var calendarIds: Set<Int>
    @State private var taskListIds: Set<Int>
    @State private var confirmRevoke = false

    init(store: DisplaysStore, display: HomeDisplay, canManage: Bool, calendars: [CalendarEntry], taskLists: [TaskListEntry]) {
        self.store = store
        self.display = display
        self.canManage = canManage
        self.calendars = calendars
        self.taskLists = taskLists
        _name = State(initialValue: display.name)
        _automaticBrightness = State(initialValue: display.settings.brightness == nil)
        _brightness = State(initialValue: display.settings.brightness ?? 0.5)
        _schedule = State(initialValue: display.settings.schedule ?? .standard)
        _scheduleOn = State(initialValue: display.settings.schedule?.enabled ?? false)
        _calendarIds = State(initialValue: Set(display.calendarIds))
        _taskListIds = State(initialValue: Set(display.taskListIds))
    }

    var body: some View {
        Form {
            Section("Nombre") {
                TextField("Nombre", text: $name).disabled(!canManage)
            }
            Section("Brillo") {
                Toggle("Automático", isOn: $automaticBrightness).disabled(!canManage)
                if !automaticBrightness {
                    Slider(value: $brightness, in: 0.05...1, step: 0.05).disabled(!canManage)
                    Text("\(Int((brightness * 100).rounded())) %")
                }
            }
            Section("Horario") {
                Toggle("Encender y apagar a horas", isOn: $scheduleOn).disabled(!canManage)
                if scheduleOn {
                    timeRow("Entre semana, enciende", minutes: $schedule.weekdayOn)
                    timeRow("Entre semana, apaga", minutes: $schedule.weekdayOff)
                    timeRow("Fin de semana, enciende", minutes: $schedule.weekendOn)
                    timeRow("Fin de semana, apaga", minutes: $schedule.weekendOff)
                    Toggle("Apagar la pantalla (si no, reloj nocturno)", isOn: $schedule.screenOff).disabled(!canManage)
                }
            }
            Section("Enseña") {
                ForEach(calendars, id: \.id) { calendar in
                    Toggle(calendar.name, isOn: binding(for: calendar.id, in: $calendarIds)).disabled(!canManage)
                }
                ForEach(taskLists, id: \.id) { list in
                    Toggle(list.name, isOn: binding(for: list.id, in: $taskListIds)).disabled(!canManage)
                }
            }
            if canManage {
                Section {
                    Button("Revocar pantalla", role: .destructive) { confirmRevoke = true }
                }
            }
        }
        .navigationTitle(display.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            if canManage {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            await store.save(display: display, name: name, settings: settings(),
                                             calendarIds: calendarIds.sorted(), taskListIds: taskListIds.sorted())
                            if store.lastError == nil { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .alert("¿Revocar la pantalla?", isPresented: $confirmRevoke) {
            Button("Revocar", role: .destructive) {
                Task {
                    await store.revoke(display)
                    dismiss()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La pantalla dejará de mostrar datos del hogar y tendrá que vincularse de nuevo.")
        }
    }

    /// Ajustes a guardar: la ubicación de la pantalla se conserva tal cual (el servidor guarda el objeto entero).
    private func settings() -> DisplaySettings {
        DisplaySettings(
            brightness: automaticBrightness ? nil : (brightness * 20).rounded() / 20,
            schedule: DisplaySchedule(enabled: scheduleOn, weekdayOn: schedule.weekdayOn, weekdayOff: schedule.weekdayOff,
                                      weekendOn: schedule.weekendOn, weekendOff: schedule.weekendOff, screenOff: schedule.screenOff),
            location: display.settings.location
        )
    }

    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        DatePicker(title, selection: Binding(
            get: { Self.date(fromMinutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = Self.minutes(from: $0) }
        ), displayedComponents: .hourAndMinute)
        .disabled(!canManage)
    }

    private func binding(for id: Int, in set: Binding<Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in
                if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
