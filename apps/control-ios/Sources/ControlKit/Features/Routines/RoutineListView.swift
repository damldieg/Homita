import SwiftUI

/// Lista de rutinas con su próxima sesión (materializada en el servidor) y las sesiones futuras
/// en solo lectura (las sesiones individuales no se editan en v1).
struct RoutineListView: View {
    @Bindable var store: RoutineStore
    let calendars: CalendarStore
    let persons: PersonStore

    @State private var showCreate = false
    @State private var routineToEdit: RoutineEntry?

    /// Sesiones futuras (solo lectura), limitadas a 10 para no alargar la lista.
    private var upcomingSessions: [EventEntry] {
        let now = PHPDateTime.format(LocalClock().now)
        return store.sessions
            .filter { $0.date_at >= now }
            .sorted { $0.date_at < $1.date_at }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        List {
            if !store.routines.isEmpty {
            Section {
                ForEach(store.routines, id: \.id) { routine in
                    RoutineRow(routine: routine, next: store.nextSession(for: routine)) {
                        routineToEdit = routine
                    }
                    .homitaRow()
                }
                .onDelete { indexSet in
                    let removed = indexSet.map { store.routines[$0] }
                    Task { for routine in removed { await store.delete(routine) } }
                }
            } header: {
                HomitaSectionHeader(title: "Rutinas", count: store.routines.count, systemImage: "repeat")
            }
            }
            if !upcomingSessions.isEmpty {
                Section {
                    ForEach(upcomingSessions, id: \.id) { session in
                        HomitaCard {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: session.calendar_color ?? Palette.fallbackItem))
                                    .frame(width: 5)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(DateDisplay.dateTime(session.date_at).uppercased())
                                        .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
                                        .foregroundStyle(Palette.inkSoft)
                                    Text(session.title)
                                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                                        .foregroundStyle(Palette.ink)
                                }
                                Spacer()
                            }
                        }
                        .homitaRow()
                    }
                } header: {
                    HomitaSectionHeader(title: "Próximas sesiones", count: upcomingSessions.count, systemImage: "calendar.badge.clock", tint: Palette.inkSoft)
                }
            }
            if store.routines.isEmpty && !store.isLoading {
                HomitaEmptyState(
                    illustration: .routines,
                    title: "Sin rutinas",
                    message: "Las rutinas repiten eventos cada día, semana o mes sin que las vuelvas a escribir.",
                    actionTitle: "Nueva rutina"
                ) {
                    showCreate = true
                }
                .homitaRow()
            }
        }
        .homitaList()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Nueva rutina")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                RoutineEditorView(store: store, calendars: calendars, persons: persons, routine: nil)
            }
        }
        .sheet(item: $routineToEdit) { routine in
            NavigationStack {
                RoutineEditorView(store: store, calendars: calendars, persons: persons, routine: routine)
            }
        }
        .refreshable {
            await store.load()
        }
        .errorAlert($store.errorMessage)
    }
}

/// Fila de rutina como tarjeta: barra del calendario, título, próxima sesión y estado.
struct RoutineRow: View {
    let routine: RoutineEntry
    let next: EventEntry?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: "Editar") { onEdit() }
    }

    private var rowContent: some View {
        HomitaCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: routine.calendar_color ?? Palette.fallbackItem))
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.title)
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    if let next {
                        Text("PRÓXIMA · \(DateDisplay.dateTime(next.date_at).uppercased())")
                            .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer()
                HomitaBadge(
                    title: routine.isActive ? "Activa" : "Pausada",
                    tintHex: routine.isActive ? Palette.onlineHex : "#A6998A"
                )
            }
        }
    }
}
