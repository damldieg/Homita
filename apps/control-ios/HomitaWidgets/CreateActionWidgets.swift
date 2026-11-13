import HomitaShared
import SwiftUI
import WidgetKit

/// Widgets de un solo botón: «Nueva tarea», «Nuevo evento» y «Nueva rutina». Cada uno abre la app
/// directamente en el formulario de alta (los widgets no admiten escribir texto, así que el
/// formulario es de la app).
enum CreateAction {
    case task, event, routine

    var kind: String {
        switch self {
        case .task: return HomitaShared.newTaskWidgetKind
        case .event: return HomitaShared.newEventWidgetKind
        case .routine: return HomitaShared.newRoutineWidgetKind
        }
    }

    var link: HomitaDeepLink {
        switch self {
        case .task: return .nuevaTarea
        case .event: return .nuevoEvento
        case .routine: return .nuevaRutina
        }
    }

    var title: String {
        switch self {
        case .task: return "Nueva tarea"
        case .event: return "Nuevo evento"
        case .routine: return "Nueva rutina"
        }
    }

    var symbol: String {
        switch self {
        case .task: return "checklist"
        case .event: return "calendar.badge.plus"
        case .routine: return "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .task: return WidgetTheme.accent
        case .event: return WidgetTheme.now
        case .routine: return WidgetTheme.soon
        }
    }
}

struct CreateActionEntry: TimelineEntry {
    let date: Date
    let enabled: Bool
}

struct CreateActionProvider: TimelineProvider {
    func placeholder(in context: Context) -> CreateActionEntry {
        CreateActionEntry(date: Date(), enabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (CreateActionEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreateActionEntry>) -> Void) {
        // Solo cambia con el toggle de Ajustes (la app recarga los widgets al cambiarlo).
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> CreateActionEntry {
        CreateActionEntry(date: Date(), enabled: NotificationPreferencesStore().load().widgets)
    }
}

struct CreateActionView: View {
    let action: CreateAction
    let entry: CreateActionEntry
    @Environment(\.widgetFamily) private var family

    private var url: URL { entry.enabled ? action.link.url : HomitaDeepLink.ajustesNotificaciones.url }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.enabled ? "plus" : "bell.slash").font(.system(size: 22, weight: .bold))
            }
            .widgetURL(url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(entry.enabled ? action.title : "Widget desactivado", systemImage: action.symbol)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.enabled ? "Toca para crear" : "Actívalo en Ajustes").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(url)
        default:
            VStack(spacing: 8) {
                Image(systemName: entry.enabled ? action.symbol : "bell.slash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(action.tint)
                Text(entry.enabled ? action.title : "Widget desactivado")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .multilineTextAlignment(.center)
                Text(entry.enabled ? "Toca para crear" : "Actívalo en Ajustes › Notificaciones")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(url)
        }
    }
}

private func createConfiguration(_ action: CreateAction, description: String) -> some WidgetConfiguration {
    StaticConfiguration(kind: action.kind, provider: CreateActionProvider()) { entry in
        CreateActionView(action: action, entry: entry)
            .containerBackground(WidgetTheme.surface, for: .widget)
    }
    .configurationDisplayName(action.title)
    .description(description)
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
}

struct NewTaskWidget: Widget {
    var body: some WidgetConfiguration { createConfiguration(.task, description: "Abre Homita para crear una tarea.") }
}

struct NewEventWidget: Widget {
    var body: some WidgetConfiguration { createConfiguration(.event, description: "Abre Homita para crear un evento.") }
}

struct NewRoutineWidget: Widget {
    var body: some WidgetConfiguration { createConfiguration(.routine, description: "Abre Homita para crear una rutina.") }
}
