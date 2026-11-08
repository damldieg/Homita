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
        _color = State(initialValue: Color(hex: calendar?.color ?? "#6923E2"))
        _widget = State(initialValue: calendar?.showsInWidget ?? true)
        _dashboard = State(initialValue: calendar?.showsInDashboard ?? true)
    }

    var body: some View {
        Form {
            Section("Calendario") {
                TextField("Nombre", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
            Section("Visible en") {
                Toggle("Widget", isOn: $widget)
                Toggle("Dashboard", isOn: $dashboard)
            }
            Section {
                Button(calendar == nil ? "Crear calendario" : "Guardar") {
                    Task { await save() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
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
                Section {
                    Button("Eliminar calendario", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(calendar == nil ? "Nuevo calendario" : "Editar calendario")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
        .task {
            if let calendar {
                await store.loadMembers(calendarId: calendar.id)
            }
        }
        .confirmationDialog(
            "Se eliminará el calendario con sus eventos.",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Eliminar calendario", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancelar", role: .cancel) {}
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
