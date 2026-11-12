import SwiftUI

/// Detalle/edición de calendario (alta con `calendar == nil`): nombre, color, flags propios
/// `widget`/`dashboard`, personas con acceso (invitar/quitar por email; owner-only en el
/// servidor) y borrado.
struct CalendarDetailView: View {
    @Bindable var store: CalendarStore
    let calendar: CalendarEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var name: String
    @State private var color: Color
    @State private var widget: Bool
    @State private var dashboard: Bool
    @State private var showDeleteConfirm = false
    @State private var isWorking = false

    init(store: CalendarStore, calendar: CalendarEntry?) {
        self.store = store
        self.calendar = calendar
        _name = State(initialValue: calendar?.name ?? "")
        _color = State(initialValue: Color(hex: calendar?.color ?? Palette.fallbackItem))
        _widget = State(initialValue: calendar?.showsInWidget ?? true)
        _dashboard = State(initialValue: calendar?.showsInDashboard ?? true)
    }

    /// Eventos y rutinas vinculados a este calendario (A4). Vacío con mensaje si no hay ninguno.
    private var linkedPanel: some View {
        HomitaPanel("Eventos y rutinas", systemImage: "list.bullet",
                    count: store.linkedEvents.count + store.linkedRoutines.count) {
            if store.linkedLoaded && store.linkedEvents.isEmpty && store.linkedRoutines.isEmpty {
                HomitaFootnote(text: "No hay eventos próximos ni rutinas vinculados a este calendario.")
            }
            ForEach(store.linkedEvents, id: \.id) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    Text(DateDisplay.dateTime(event.date_at))
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            ForEach(store.linkedRoutines, id: \.id) { routine in
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.title)
                        .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    Text("Rutina · \(routine.time)")
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("Calendario", systemImage: "calendar") {
                HomitaField(placeholder: "Nombre", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
            }
            HomitaPanel("Visible en", systemImage: "eye") {
                HomitaToggle(title: "Widget", isOn: $widget)
                HomitaToggle(title: "Dashboard", isOn: $dashboard)
            }
            if calendar != nil {
                linkedPanel
            }
            HomitaButton(
                title: calendar == nil ? "Crear calendario" : "Guardar",
                isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking,
                isLoading: isWorking
            ) {
                Task { await save() }
            }
            if calendar != nil {
                MembersSection(
                    members: store.members,
                    currentUserId: session.session?.id,
                    onInvite: { email in
                        Task { await store.invite(calendarId: calendar?.id ?? 0, email: email) }
                    },
                    onRemove: { userId in
                        Task { await store.removeMember(calendarId: calendar?.id ?? 0, userId: userId) }
                    }
                )
                HomitaButton(title: "Eliminar calendario", kind: .secondary) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle(calendar == nil ? "Nuevo calendario" : "Editar calendario")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
        .task {
            if let calendar {
                await store.loadMembers(calendarId: calendar.id)
                await store.loadLinked(calendarId: calendar.id)
            }
        }
        .homitaConfirm("Se eliminará el calendario con sus eventos.", isPresented: $showDeleteConfirm, confirmTitle: "Eliminar calendario") {
            Task { await delete() }
        }
        .errorAlert($store.errorMessage)
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        let ok = await store.save(
            name: name.trimmingCharacters(in: .whitespaces),
            color: color.hexString,
            widget: widget,
            dashboard: dashboard,
            editing: calendar
        )
        if ok { dismiss() }
    }

    private func delete() async {
        guard let calendar else { return }
        isWorking = true
        defer { isWorking = false }
        await store.delete(calendar)
        dismiss()
    }
}
