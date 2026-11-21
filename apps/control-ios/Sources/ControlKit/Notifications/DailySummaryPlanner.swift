import Foundation
import HomitaShared

/// Contenido del resumen diario ya calculado.
public struct DailySummary: Equatable, Sendable {
    public let title: String
    public let body: String
    public let eventCount: Int
    public let taskCount: Int
    public let link: HomitaDeepLink
}

/// Selecciona lo que entra en el resumen diario: las tareas pendientes asignadas al usuario y sus
/// eventos del día (puntuales y de todo el día). Lógica pura. Las rutinas no entran (D-B5).
public enum DailySummaryPlanner {
    /// Títulos que se muestran en el cuerpo.
    public static let maxTitles = 3
    public static let identifier = "homita.dailysummary"

    /// `nil` si no hay nada que avisar (se omite la notificación) o si la cuenta no tiene persona vinculada.
    public static func summary(
        events: [EventEntry], tasks: [TaskEntry], myPersonIds: Set<Int>?, day: Date, timeZone: TimeZone = .current
    ) -> DailySummary? {
        guard let ids = myPersonIds, !ids.isEmpty else { return nil }
        func isMine(_ persons: [PersonEntry]?) -> Bool { (persons ?? []).contains { ids.contains($0.id) } }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Sesiones de rutina (S-1) y eventos de varios días quedan fuera.
        let todays = TodaySummary.events(events, on: day, timeZone: timeZone).filter {
            $0.routine_id == nil && $0.validEndDay == nil && isMine($0.persons)
        }
        let pending = TodaySummary.pendingTasks(tasks, limit: tasks.count).filter { isMine($0.persons) }
        guard !todays.isEmpty || !pending.isEmpty else { return nil }

        // Primero eventos (por hora), luego tareas.
        var items: [String] = todays.map { event in
            guard let date = PHPDateTime.parse(event.date_at, timeZone: timeZone) else { return event.title }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            // D-B2: 00:00 = todo el día.
            let time = (parts.hour == 0 && parts.minute == 0)
                ? "Todo el día" : NotificationPlanner.timeText(date, timeZone: timeZone)
            return "\(time) \(event.title)"
        }
        items += pending.map(\.title)

        var counts: [String] = []
        if !todays.isEmpty { counts.append(todays.count == 1 ? "1 evento" : "\(todays.count) eventos") }
        if !pending.isEmpty { counts.append(pending.count == 1 ? "1 tarea" : "\(pending.count) tareas") }
        let body = counts.joined(separator: ", ") + ": " + items.prefix(maxTitles).joined(separator: ", ")
            + (items.count > maxTitles ? "…" : "")

        return DailySummary(
            title: "Tu resumen de hoy", body: body, eventCount: todays.count, taskCount: pending.count,
            link: todays.isEmpty ? .tareas : .calendario
        )
    }
}
