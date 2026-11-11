import SwiftUI

/// Lista de eventos: próximos y pasados (filtros del contrato por query), filtro por calendario,
/// búsqueda por `search` y alta. Cada fila abre `EventDetailView` (editor). Las sesiones de
/// rutina llegan con `routine_id` y se marcan en la fila.
struct EventListView: View {
    @Bindable var store: EventStore
    let calendars: CalendarStore
    let persons: PersonStore

    @State private var searchText = ""
    @State private var showCreate = false
    @State private var eventToEdit: EventEntry?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Buscar eventos", text: $searchText)
                    Button {
                        store.searchText = searchText
                        Task { await store.load() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if !store.upcoming.isEmpty {
                Section("Próximos") {
                    ForEach(store.upcoming, id: \.id) { event in
                        EventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture { eventToEdit = event }
                            .accessibilityAction(named: "Editar") { eventToEdit = event }
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.upcoming[$0] }
                        Task { for event in removed { await store.delete(event) } }
                    }
                }
            }
            if !store.past.isEmpty {
                Section("Pasados") {
                    ForEach(store.past, id: \.id) { event in
                        EventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture { eventToEdit = event }
                            .accessibilityAction(named: "Editar") { eventToEdit = event }
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.past[$0] }
                        Task { for event in removed { await store.delete(event) } }
                    }
                    if store.hasMorePast {
                        Button("Cargar más") {
                            Task { await store.loadMorePast() }
                        }
                        .disabled(store.isLoadingMore)
                    }
                }
            }
            if store.upcoming.isEmpty && store.past.isEmpty && !store.isLoading {
                Text("Sin eventos")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Todos los calendarios") {
                        store.calendarFilterId = nil
                        Task { await store.load() }
                    }
                    ForEach(calendars.calendars, id: \.id) { calendar in
                        Button(calendar.name) {
                            store.calendarFilterId = calendar.id
                            Task { await store.load() }
                        }
                    }
                } label: {
                    Label("Filtrar", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Label("Nuevo evento", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                EventDetailView(store: store, calendars: calendars, persons: persons, event: nil)
            }
        }
        .sheet(item: $eventToEdit) { event in
            NavigationStack {
                EventDetailView(store: store, calendars: calendars, persons: persons, event: event)
            }
        }
        .refreshable {
            await store.load()
        }
        .errorAlert($store.errorMessage)
    }
}

/// Fila de evento: color del calendario, título, fecha/hora, alarma y si es sesión de rutina.
struct EventRow: View {
    let event: EventEntry

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: event.calendar_color ?? "#6923E2"))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(event.title)
                Text(DateDisplay.dateTime(event.date_at))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if event.routine_id != nil {
                Image(systemName: "repeat")
                    .foregroundStyle(.secondary)
            }
            if event.alarm != nil {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
