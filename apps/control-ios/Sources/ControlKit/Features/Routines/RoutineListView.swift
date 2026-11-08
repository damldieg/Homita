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
            Section("Rutinas") {
                ForEach(store.routines, id: \.id) { routine in
                    RoutineRow(routine: routine, next: store.nextSession(for: routine))
                        .contentShape(Rectangle())
                        .onTapGesture { routineToEdit = routine }
                }
                .onDelete { indexSet in
                    let removed = indexSet.map { store.routines[$0] }
                    Task { for routine in removed { await store.delete(routine) } }
                }
            }
            if !upcomingSessions.isEmpty {
                Section("Próximas sesiones (solo lectura)") {
                    ForEach(upcomingSessions, id: \.id) { session in
                        HStack {
                            Circle()
                                .fill(Color(hex: session.calendar_color ?? "#6923E2"))
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading) {
                                Text(session.title)
                                Text(session.date_at)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if store.routines.isEmpty && !store.isLoading {
                Text("Sin rutinas")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Label("Nueva rutina", systemImage: "plus")
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

/// Fila de rutina: calendario, título, próxima sesión y estado activa/pausada.
struct RoutineRow: View {
    let routine: RoutineEntry
    let next: EventEntry?

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: routine.calendar_color ?? "#6923E2"))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(routine.title)
                if let next {
                    Text("Próxima: \(next.date_at)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(routine.isActive ? "Activa" : "Pausada")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
