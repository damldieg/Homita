import HomitaShared
import SwiftUI
import WidgetKit

// MARK: - Datos

/// Qué puede mostrar el widget de rutinas.
enum RoutinesAvailability {
    case ok
    /// Toggle «Datos en widgets» apagado en Ajustes.
    case disabled
    /// Sin sesión en la app.
    case signedOut
    /// La app aún no dejó datos (primera vez o sin App Group).
    case noData
}

struct RoutinesEntry: TimelineEntry {
    let date: Date
    let availability: RoutinesAvailability
    let snapshot: HomitaSnapshot?

    /// Rutinas de la foto, solo si pertenece al día de la entrada.
    var currentSnapshot: HomitaSnapshot? {
        guard availability == .ok, let snapshot, !snapshot.isStale(at: date) else { return nil }
        return snapshot
    }
}

struct RoutinesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutinesEntry {
        RoutinesEntry(date: Date(), availability: .ok, snapshot: Self.sample(now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutinesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.load(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutinesEntry>) -> Void) {
        let now = Date()
        let first = Self.load(at: now)
        var entries = [first]
        if let snapshot = first.snapshot, first.availability == .ok {
            // Una entrada en cada cambio de fase (inicio − 1 h, inicio, inicio + 1 h) y otra a medianoche.
            for date in snapshot.boundaries(after: now).prefix(30) {
                entries.append(RoutinesEntry(date: date, availability: .ok, snapshot: snapshot))
            }
            if let midnight = Calendar.current.nextDate(
                after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
            ) {
                entries.append(RoutinesEntry(date: midnight, availability: .ok, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func load(at now: Date) -> RoutinesEntry {
        guard NotificationPreferencesStore().load().widgets else {
            return RoutinesEntry(date: now, availability: .disabled, snapshot: nil)
        }
        guard let snapshot = SnapshotStore().load() else {
            return RoutinesEntry(date: now, availability: .noData, snapshot: nil)
        }
        return RoutinesEntry(date: now, availability: snapshot.signedIn ? .ok : .signedOut, snapshot: snapshot)
    }

    /// Datos de muestra para la galería de widgets.
    static func sample(now: Date) -> HomitaSnapshot {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }
        return HomitaSnapshot(
            generatedAt: now, dayStart: calendar.startOfDay(for: now), homeName: "Casa",
            routines: [
                .init(id: 1, title: "Desayuno", colorHex: "#0E9F6E", start: at(8, 0)),
                .init(id: 2, title: "Deberes", colorHex: "#6D28D9", start: at(17, 30)),
                .init(id: 3, title: "Baño", colorHex: "#0284C7", start: at(20, 0)),
            ]
        )
    }
}

// MARK: - Widget

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomitaShared.routinesWidgetKind, provider: RoutinesProvider()) { entry in
            RoutinesWidgetView(entry: entry)
                .containerBackground(WidgetTheme.surface, for: .widget)
        }
        .configurationDisplayName("Rutinas de hoy")
        .description("La rutina en curso o la próxima, y las del resto del día.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Vistas

struct RoutinesWidgetView: View {
    let entry: RoutinesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.currentSnapshot {
                content(snapshot)
            } else {
                message
            }
        }
        .widgetURL(entry.availability == .disabled ? HomitaDeepLink.ajustesNotificaciones.url : HomitaDeepLink.rutinas.url)
    }

    // MARK: Contenido

    @ViewBuilder
    private func content(_ snapshot: HomitaSnapshot) -> some View {
        switch family {
        case .accessoryInline:
            inline(snapshot)
        case .accessoryRectangular:
            rectangular(snapshot)
        case .systemSmall:
            small(snapshot)
        case .systemMedium:
            list(snapshot, limit: 3)
        default:
            list(snapshot, limit: 7)
        }
    }

    private func inline(_ snapshot: HomitaSnapshot) -> some View {
        Group {
            if let focus = snapshot.focusRoutine(at: entry.date), let start = focus.start {
                Text("\(focus.title) · \(start, style: .time)")
            } else {
                Text(snapshot.routines.isEmpty ? "Sin rutinas hoy" : "Rutinas hechas")
            }
        }
    }

    private func rectangular(_ snapshot: HomitaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Rutinas", systemImage: "arrow.triangle.2.circlepath").font(.caption2)
            if let focus = snapshot.focusRoutine(at: entry.date), let start = focus.start {
                Text(focus.title).font(.headline).lineLimit(1)
                Text("\(label(for: focus.phase(at: entry.date))) · \(start, style: .time)").font(.caption)
            } else {
                Text(snapshot.routines.isEmpty ? "Sin rutinas hoy" : "Todo hecho por hoy").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ snapshot: HomitaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(snapshot)
            Spacer(minLength: 0)
            if let focus = snapshot.focusRoutine(at: entry.date) {
                let phase = focus.phase(at: entry.date)
                Text(label(for: phase).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color(for: phase))
                Text(focus.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                if let start = focus.start {
                    Text(start, style: .time).font(.system(size: 14, weight: .medium)).foregroundStyle(WidgetTheme.inkSoft)
                }
            } else {
                Text(snapshot.routines.isEmpty ? "Sin rutinas hoy" : "Todo hecho por hoy")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetTheme.ink)
            }
            Spacer(minLength: 0)
            progressLine(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func list(_ snapshot: HomitaSnapshot, limit: Int) -> some View {
        // En curso y próximas primero; las hechas al final.
        let upcoming = snapshot.routines.filter { $0.phase(at: entry.date) != .done }
        let done = snapshot.routines.filter { $0.phase(at: entry.date) == .done }
        let rows = Array((upcoming + done).prefix(limit))
        return VStack(alignment: .leading, spacing: 8) {
            header(snapshot)
            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("Sin rutinas hoy").font(.system(size: 15, weight: .medium)).foregroundStyle(WidgetTheme.inkSoft)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { routine in row(routine) }
                Spacer(minLength: 0)
            }
            progressLine(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func header(_ snapshot: HomitaSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetTheme.accent)
            Text("Rutinas de hoy")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetTheme.ink)
        }
    }

    private func row(_ routine: HomitaSnapshot.Routine) -> some View {
        let phase = routine.phase(at: entry.date)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: routine.colorHex)).frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(routine.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(phase == .done ? WidgetTheme.inkSoft : WidgetTheme.ink)
                    .strikethrough(phase == .done)
                    .lineLimit(1)
                Text(label(for: phase))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color(for: phase))
            }
            Spacer(minLength: 4)
            if let start = routine.start {
                Text(start, style: .time).font(.system(size: 13, weight: .semibold)).foregroundStyle(WidgetTheme.inkSoft)
            }
        }
    }

    private func progressLine(_ snapshot: HomitaSnapshot) -> some View {
        let total = snapshot.routines.count
        let done = snapshot.doneCount(at: entry.date)
        return VStack(alignment: .leading, spacing: 3) {
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total)).tint(WidgetTheme.now)
                Text("\(done) de \(total) hechas").font(.system(size: 11, weight: .medium)).foregroundStyle(WidgetTheme.inkSoft)
            }
        }
    }

    // MARK: Mensajes

    private var message: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.title3).foregroundStyle(WidgetTheme.accent)
            Text(messageText).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                .foregroundStyle(WidgetTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageText: String {
        switch entry.availability {
        case .disabled: return "Widget desactivado. Actívalo en Ajustes › Notificaciones."
        case .signedOut: return "Inicia sesión en Homita."
        case .noData: return "Abre Homita para cargar tus rutinas."
        case .ok: return "Abre Homita para actualizar las rutinas de hoy."
        }
    }

    // MARK: Fases

    private func label(for phase: SnapshotRoutinePhase) -> String {
        switch phase {
        case .done: return "Hecha"
        case .now: return "En curso"
        case .soon: return "Pronto"
        case .later: return "Más tarde"
        case .anytime: return "Sin hora"
        }
    }

    private func color(for phase: SnapshotRoutinePhase) -> Color {
        switch phase {
        case .now: return WidgetTheme.now
        case .soon: return WidgetTheme.soon
        default: return WidgetTheme.inkSoft
        }
    }
}
