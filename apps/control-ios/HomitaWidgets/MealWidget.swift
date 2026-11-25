import HomitaShared
import SwiftUI
import WidgetKit

// MARK: - Datos

struct MealEntry: TimelineEntry {
    let date: Date
    let availability: RoutinesAvailability
    let snapshot: HomitaSnapshot?

    /// Casillas de hoy; vacío si no hay menú aceptado, no hay dato o el dato es de otro día.
    var items: [HomitaSnapshot.Meals.Item] {
        guard availability == .ok, let meals = snapshot?.meals else { return [] }
        return meals.visibleItems(at: date)
    }

    /// Índice de la franja actual dentro de `items`.
    var currentIndex: Int? {
        guard availability == .ok, let meals = snapshot?.meals else { return nil }
        return meals.currentIndex(at: date)
    }
}

struct MealProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealEntry {
        MealEntry(date: Date(), availability: .ok, snapshot: Self.sample(now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.load(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        let now = Date()
        let first = Self.load(at: now)
        var entries = [first]
        if let snapshot = first.snapshot, first.availability == .ok {
            // Una entrada en la hora de cada franja y otra a medianoche (cambia el día).
            for date in (snapshot.meals?.boundaries(after: now) ?? []).prefix(30) {
                entries.append(MealEntry(date: date, availability: .ok, snapshot: snapshot))
            }
            if let midnight = Calendar.current.nextDate(
                after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
            ) {
                entries.append(MealEntry(date: midnight, availability: .ok, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func load(at now: Date) -> MealEntry {
        guard NotificationPreferencesStore().load().widgets else {
            return MealEntry(date: now, availability: .disabled, snapshot: nil)
        }
        guard let snapshot = SnapshotStore().load() else {
            return MealEntry(date: now, availability: .noData, snapshot: nil)
        }
        return MealEntry(date: now, availability: snapshot.signedIn ? .ok : .signedOut, snapshot: snapshot)
    }

    /// Datos de muestra para la galería de widgets.
    static func sample(now: Date) -> HomitaSnapshot {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
        return HomitaSnapshot(
            generatedAt: now, dayStart: calendar.startOfDay(for: now), homeName: "Casa",
            meals: .init(date: day, timezone: TimeZone.current.identifier, hasPlan: true, items: [
                .init(slot: "breakfast", time: "08:00", title: "Tostadas con tomate"),
                .init(slot: "lunch", time: "14:00", title: "Lentejas con arroz"),
                .init(slot: "snack", time: "17:30", title: "Fruta y yogur"),
                .init(slot: "dinner", time: "21:00", title: "Tortilla de patatas"),
            ])
        )
    }
}

// MARK: - Widget

struct MealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomitaShared.mealWidgetKind, provider: MealProvider()) { entry in
            MealWidgetView(entry: entry)
                .containerBackground(WidgetTheme.surface, for: .widget)
        }
        .configurationDisplayName("Hoy se come")
        .description("La comida que toca ahora o la próxima, y el resto del menú de hoy.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Vistas

struct MealWidgetView: View {
    let entry: MealEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.availability {
            case .ok:
                if entry.items.isEmpty { message("Sin menú hoy") } else { content }
            case .disabled: message("Widget desactivado. Actívalo en Ajustes › Notificaciones.")
            case .signedOut: message("Inicia sesión en Homita.")
            case .noData: message("Abre Homita para cargar el menú.")
            }
        }
        .widgetURL(entry.availability == .disabled ? HomitaDeepLink.ajustesNotificaciones.url : HomitaDeepLink.menu.url)
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall { small } else { list(limit: 4) }
    }

    private var small: some View {
        let items = entry.items
        let index = entry.currentIndex
        return VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let index {
                let item = items[index]
                Text(MealWidgetLabels.slotTitle(item.slot).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.now)
                Text(item.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(3)
                Text(item.time).font(.system(size: 14, weight: .medium)).foregroundStyle(WidgetTheme.inkSoft)
            } else {
                Text("Hoy ya está todo servido")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetTheme.ink)
            }
            Spacer(minLength: 0)
            if let index, index + 1 < items.count {
                Text("Luego: \(items[index + 1].title)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func list(limit: Int) -> some View {
        let items = entry.items
        let index = entry.currentIndex
        // Ventana de `limit` casillas que arranca en la actual (o en las últimas si ya pasaron todas).
        let lastStart = max(items.count - limit, 0)
        let shown = Array(items.enumerated()).dropFirst(min(index ?? lastStart, lastStart)).prefix(limit)
        return VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(Array(shown), id: \.element.id) { offset, item in
                row(item, isCurrent: offset == index, isPast: index.map { offset < $0 } ?? true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetTheme.accent)
            Text("Hoy se come")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetTheme.ink)
        }
    }

    private func row(_ item: HomitaSnapshot.Meals.Item, isCurrent: Bool, isPast: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isCurrent ? WidgetTheme.now : WidgetTheme.line)
                .frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isPast ? WidgetTheme.inkSoft : WidgetTheme.ink)
                    .lineLimit(1)
                Text(MealWidgetLabels.slotTitle(item.slot))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isCurrent ? WidgetTheme.now : WidgetTheme.inkSoft)
            }
            Spacer(minLength: 4)
            Text(item.time).font(.system(size: 13, weight: .semibold)).foregroundStyle(WidgetTheme.inkSoft)
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife").font(.title3).foregroundStyle(WidgetTheme.accent)
            Text(text).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                .foregroundStyle(WidgetTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nombres de franja (la extensión no enlaza `ControlKit`, así que no usa `MealSlotKind`).
enum MealWidgetLabels {
    static func slotTitle(_ slot: String) -> String {
        switch slot {
        case "breakfast": return "Desayuno"
        case "midmorning": return "Media mañana"
        case "lunch": return "Comida"
        case "snack": return "Merienda"
        case "dinner": return "Cena"
        default: return slot
        }
    }
}
