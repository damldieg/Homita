import SwiftUI

/// Lista de rutinas agrupadas por día (Hoy, Mañana, Próxima semana) con su próxima sesión;
/// las de hoy ya caducadas se muestran deshabilitadas (las sesiones individuales no se editan en v1).
struct RoutineListView: View {
    @Bindable var store: RoutineStore
    let calendars: CalendarStore
    let persons: PersonStore

    @State private var showCreate = false
    @State private var routineToEdit: RoutineEntry?

    var body: some View {
        List {
            ForEach(store.routineSections, id: \.group) { section in
                Section {
                    ForEach(section.routines, id: \.id) { routine in
                        RoutineRow(routine: routine, next: store.nextSession(for: routine), status: store.status(for: routine, in: section.group)) {
                            routineToEdit = routine
                        }
                        .homitaRow()
                    }
                    .onDelete { indexSet in
                        let removed = indexSet.map { section.routines[$0] }
                        Task { for routine in removed { await store.delete(routine) } }
                    }
                } header: {
                    HomitaSectionHeader(title: section.group.title, count: section.routines.count, systemImage: "repeat")
                }
            }
            if !store.hasLoaded || (store.isLoading && store.routines.isEmpty) {
                HomitaLoadingCard(message: "Cargando rutinas…").homitaRow()
            }
            if store.hasLoaded && store.routines.isEmpty && !store.isLoading {
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
    var status: RoutineStatus = .normal
    /// Dentro de otra tarjeta (Inicio): sin tarjeta propia, con margen interno y hora de inicio.
    var embedded = false
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: "Editar") { onEdit() }
    }

    @ViewBuilder
    private var rowContent: some View {
        if embedded {
            rowBody
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(statusBackground, in: RoundedRectangle(cornerRadius: 16))
                .opacity(status == .expired ? 0.7 : 1)
        } else {
            HomitaCard { rowBody }
                .routineStatusStyle(status)
        }
    }

    /// Hora de inicio «HH:mm» o «Sin hora» si la rutina no tiene hora fija.
    private var timeText: String {
        guard routine.hasFixedTime else { return "Sin hora" }
        return String(routine.time.prefix(5))
    }

    private var rowBody: some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: routine.calendar_color ?? Palette.fallbackItem))
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if status == .expired {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityLabel("Hecha")
                        }
                        Text(routine.title)
                            .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(status == .expired ? Palette.inkMuted : Palette.ink)
                            .strikethrough(status == .expired)
                    }
                    if embedded {
                        Text(timeText)
                            .font(HomitaFont.geist(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    AssignedPersonTags(persons: routine.persons)
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

    private var statusBackground: Color {
        switch status {
        case .expired: Palette.inkMuted.opacity(0.28)
        case .inProgress: Palette.accent.opacity(0.12)
        case .normal: .clear
        }
    }
}

extension View {
    /// Estado visual de rutina compartido (pestaña Rutinas e Inicio): caducada gris y atenuada,
    /// en curso resaltada, normal sin cambios.
    func routineStatusStyle(_ status: RoutineStatus) -> some View {
        let background: Color
        switch status {
        case .expired: background = Palette.inkMuted.opacity(0.28)
        case .inProgress: background = Palette.accent.opacity(0.12)
        case .normal: background = .clear
        }
        return self
            .background(background, in: RoundedRectangle(cornerRadius: 24))
            .opacity(status == .expired ? 0.7 : 1)
    }
}
