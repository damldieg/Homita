import HomitaShared
import SwiftUI
import WidgetKit

struct QuickActionsEntry: TimelineEntry {
    let date: Date
    let enabled: Bool
    let pendingTasks: Int
    let eventsToday: Int
}

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date(), enabled: true, pendingTasks: 3, eventsToday: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func load() -> QuickActionsEntry {
        let now = Date()
        guard NotificationPreferencesStore().load().widgets else {
            return QuickActionsEntry(date: now, enabled: false, pendingTasks: 0, eventsToday: 0)
        }
        let snapshot = SnapshotStore().load()
        let fresh = snapshot.flatMap { $0.isStale(at: now) ? nil : $0 }
        return QuickActionsEntry(
            date: now, enabled: true, pendingTasks: snapshot?.pendingTaskCount ?? 0, eventsToday: fresh?.events.count ?? 0
        )
    }
}

/// Accesos rápidos: crear tarea, crear evento y ver las rutinas. Cada botón abre la app con un
/// enlace profundo (`homita://nueva-tarea`, …) y la app abre directamente el formulario.
struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomitaShared.quickActionsWidgetKind, provider: QuickActionsProvider()) { entry in
            QuickActionsView(entry: entry)
                .containerBackground(WidgetTheme.surface, for: .widget)
        }
        .configurationDisplayName("Accesos rápidos")
        .description("Crea una tarea o un evento y mira las rutinas con un toque.")
        .supportedFamilies([.systemMedium, .accessoryCircular])
    }
}

struct QuickActionsView: View {
    let entry: QuickActionsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus").font(.system(size: 22, weight: .bold))
            }
            .widgetURL(entry.enabled ? HomitaDeepLink.nuevaTarea.url : HomitaDeepLink.ajustesNotificaciones.url)
        } else if entry.enabled {
            HStack(spacing: 10) {
                tile("Tarea", systemImage: "checklist", detail: detail(entry.pendingTasks, "pendiente", "pendientes"),
                     tint: WidgetTheme.accent, link: .nuevaTarea)
                tile("Evento", systemImage: "calendar.badge.plus", detail: detail(entry.eventsToday, "hoy", "hoy"),
                     tint: WidgetTheme.now, link: .nuevoEvento)
                tile("Rutinas", systemImage: "arrow.triangle.2.circlepath", detail: "Ver hoy",
                     tint: WidgetTheme.soon, link: .rutinas)
            }
        } else {
            Link(destination: HomitaDeepLink.ajustesNotificaciones.url) {
                Text("Widget desactivado. Actívalo en Ajustes › Notificaciones.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detail(_ count: Int, _ one: String, _ many: String) -> String {
        count == 0 ? "Nueva" : "\(count) \(count == 1 ? one : many)"
    }

    private func tile(_ title: String, systemImage: String, detail: String, tint: Color, link: HomitaDeepLink) -> some View {
        Link(destination: link.url) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(WidgetTheme.ink)
                Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(WidgetTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
