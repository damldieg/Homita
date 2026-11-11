import SwiftUI

/// Lista de calendarios: color, nombre y próximos eventos; alta y navegación al detalle
/// (edición + invitaciones).
struct CalendarListView: View {
    @Bindable var store: CalendarStore
    @State private var showCreate = false

    var body: some View {
        List {
            if store.calendars.isEmpty && !store.isLoading {
                HomitaEmptyState(
                    illustration: .calendars,
                    title: "Sin calendarios",
                    message: "Los calendarios agrupan eventos y rutinas por color, como Trabajo o Familia.",
                    actionTitle: "Nuevo calendario"
                ) {
                    showCreate = true
                }
                .homitaRow()
            }
            if !store.calendars.isEmpty {
            Section {
                ForEach(store.calendars, id: \.id) { calendar in
                    NavigationLink {
                        CalendarDetailView(store: store, calendar: calendar)
                    } label: {
                        HomitaCard {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: calendar.color))
                                    .frame(width: 14, height: 14)
                                Text(calendar.name)
                                    .font(HomitaFont.geist(17, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                HomitaBadge(title: "\(calendar.upcomingEventCount)", tintHex: calendar.color)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .homitaRow()
                }
            } header: {
                HomitaSectionHeader(title: "Calendarios", count: store.calendars.count, systemImage: "calendar")
            }

            Section {
                Button {
                    showCreate = true
                } label: {
                    HomitaCard {
                        Label("Nuevo calendario", systemImage: "plus")
                            .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .buttonStyle(.plain)
                .homitaRow()
            }
            }
        }
        .homitaList()
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CalendarDetailView(store: store, calendar: nil)
            }
        }
        .refreshable {
            await store.load()
        }
        .errorAlert($store.errorMessage)
    }
}
