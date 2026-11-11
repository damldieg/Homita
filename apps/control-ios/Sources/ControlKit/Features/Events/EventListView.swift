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
                HomitaCard {
                    HStack(spacing: 10) {
                        HomitaField(placeholder: "Buscar eventos", text: $searchText)
                            .onSubmit {
                                store.searchText = searchText
                                Task { await store.load() }
                            }
                        Button {
                            store.searchText = searchText
                            Task { await store.load() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .homitaRow()
            }
            if !store.upcoming.isEmpty {
                Section {
                    ForEach(store.upcoming, id: \.id) { event in
                        EventRow(event: event) { eventToEdit = event }
                            .homitaRow()
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.upcoming[$0] }
                        Task { for event in removed { await store.delete(event) } }
                    }
                } header: {
                    HomitaSectionHeader(title: "Próximos", count: store.upcoming.count, systemImage: "calendar")
                }
            }
            if !store.past.isEmpty {
                Section {
                    ForEach(store.past, id: \.id) { event in
                        EventRow(event: event) { eventToEdit = event }
                            .homitaRow()
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { store.past[$0] }
                        Task { for event in removed { await store.delete(event) } }
                    }
                    if store.hasMorePast {
                        Button {
                            Task { await store.loadMorePast() }
                        } label: {
                            HomitaCard {
                                Text("Cargar más")
                                    .font(HomitaFont.geist(16, weight: .medium, relativeTo: .body))
                                    .foregroundStyle(Palette.accent)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoadingMore)
                        .homitaRow()
                    }
                } header: {
                    HomitaSectionHeader(title: "Pasados", count: store.past.count, systemImage: "clock.arrow.circlepath", tint: Palette.inkSoft)
                }
            }
            if store.upcoming.isEmpty && store.past.isEmpty && !store.isLoading {
                HomitaEmptyState(
                    systemImage: "calendar.badge.plus",
                    title: "Sin eventos",
                    message: "Añade un evento con fecha y hora para verlo aquí.",
                    actionTitle: "Nuevo evento"
                ) {
                    showCreate = true
                }
                .homitaRow()
            }
        }
        .homitaList()
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
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Filtrar")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Nuevo evento")
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

/// Fila de evento como tarjeta: barra del color del calendario, fecha en mayúsculas, título e
/// iconos de rutina y alarma. Toque o acción «Editar» abre el editor.
struct EventRow: View {
    let event: EventEntry
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
                    .fill(Color(hex: event.calendar_color ?? Palette.fallbackItem))
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(DateDisplay.dateTime(event.date_at).uppercased())
                        .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Palette.inkSoft)
                    Text(event.title)
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                }
                Spacer()
                HStack(spacing: 8) {
                    if event.routine_id != nil {
                        Image(systemName: "repeat")
                            .foregroundStyle(Palette.inkSoft)
                    }
                    if event.alarm != nil {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(Palette.warm)
                    }
                }
            }
        }
    }
}
