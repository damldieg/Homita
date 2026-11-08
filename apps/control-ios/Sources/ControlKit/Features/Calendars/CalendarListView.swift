import SwiftUI

/// Lista de calendarios: color, nombre y próximos eventos; alta y navegación al detalle
/// (edición + invitaciones).
struct CalendarListView: View {
    @Bindable var store: CalendarStore
    @State private var showCreate = false

    var body: some View {
        List {
            ForEach(store.calendars, id: \.id) { calendar in
                NavigationLink {
                    CalendarDetailView(store: store, calendar: calendar)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: calendar.color))
                            .frame(width: 12, height: 12)
                        Text(calendar.name)
                        Spacer()
                        Text("\(calendar.upcomingEventCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                showCreate = true
            } label: {
                Label("Nuevo calendario", systemImage: "plus")
            }
        }
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
