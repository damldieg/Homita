import Foundation
import HomitaShared

/// Un aviso local ya calculado (sin tocar el sistema): el scheduler lo convierte en notificación.
public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case event, routine, taskDigest
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let fireDate: Date
    public let link: HomitaDeepLink
}

/// Calcula qué avisos locales programar a partir de los datos del hogar y de las preferencias.
/// Lógica pura: iOS limita a 64 notificaciones pendientes, por eso se programan solo las más próximas.
public enum NotificationPlanner {
    /// Tope de avisos pendientes (iOS permite 64; se deja margen).
    public static let maxPending = 60
    /// Días hacia delante que se calculan para rutinas y resumen de tareas.
    public static let horizonDays = 7

    public static func plan(
        events: [EventEntry], routines: [RoutineEntry], pendingTasks: [TaskEntry],
        preferences: NotificationPreferences, now: Date, timeZone: TimeZone = .current,
        myPersonIds: Set<Int>? = nil
    ) -> [PlannedNotification] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var result: [PlannedNotification] = []
        if preferences.eventReminders {
            result += eventNotifications(events, now: now, timeZone: timeZone)
        }
        if preferences.routineReminders {
            // Con `myPersonIds` solo avisan las rutinas asignadas a la persona de esta cuenta
            // (conjunto vacío = cuenta sin persona vinculada: ninguna). `nil` = sin filtro.
            let mine = myPersonIds.map { ids in
                routines.filter { routine in (routine.persons ?? []).contains { ids.contains($0.id) } }
            } ?? routines
            result += routineNotifications(mine, now: now, calendar: calendar, timeZone: timeZone)
        }
        if preferences.taskDigest {
            result += digestNotifications(pendingTasks, preferences: preferences, now: now, calendar: calendar)
        }
        return Array(
            result.sorted { $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.id < $1.id }
                .prefix(maxPending)
        )
    }

    // MARK: - Eventos

    static func eventNotifications(_ events: [EventEntry], now: Date, timeZone: TimeZone) -> [PlannedNotification] {
        events.compactMap { event in
            // Las sesiones de rutina las cubre el aviso de la rutina (evita duplicados).
            guard event.routine_id == nil, let alarm = event.alarm, alarm >= 0,
                  let start = PHPDateTime.parse(event.date_at, timeZone: timeZone) else { return nil }
            let fire = start.addingTimeInterval(-Double(alarm) * 60)
            guard fire > now else { return nil }
            return PlannedNotification(
                id: "homita.event.\(event.id).\(Int(start.timeIntervalSince1970))",
                kind: .event, title: event.title,
                body: body(lead: alarm, start: start, timeZone: timeZone, extra: event.calendar_name),
                fireDate: fire, link: .calendario
            )
        }
    }

    // MARK: - Rutinas

    static func routineNotifications(
        _ routines: [RoutineEntry], now: Date, calendar: Calendar, timeZone: TimeZone
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        let today = calendar.startOfDay(for: now)
        for routine in routines where routine.isActive {
            // Sin `alarm` el usuario eligió «sin aviso»: se respeta.
            guard let alarm = routine.alarm, alarm >= 0, let rule = routine.rule(timeZone: timeZone) else { continue }
            for offset in 0..<horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      rule.occurs(on: day, timeZone: timeZone),
                      let start = RoutineStatus.startToday(time: routine.time, now: day, timeZone: timeZone) else { continue }
                let fire = start.addingTimeInterval(-Double(alarm) * 60)
                guard fire > now else { continue }
                result.append(PlannedNotification(
                    id: "homita.routine.\(routine.id).\(dayKey(day, calendar: calendar))",
                    kind: .routine, title: routine.title,
                    body: body(lead: alarm, start: start, timeZone: timeZone, extra: personsText(routine.persons)),
                    fireDate: fire, link: .rutinas
                ))
            }
        }
        return result
    }

    // MARK: - Resumen de tareas

    static func digestNotifications(
        _ tasks: [TaskEntry], preferences: NotificationPreferences, now: Date, calendar: Calendar
    ) -> [PlannedNotification] {
        let pending = tasks.filter { !$0.isCompleted }
        guard !pending.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [PlannedNotification] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(
                    bySettingHour: preferences.taskDigestHour, minute: preferences.taskDigestMinute, second: 0, of: day
                  ), fire > now else { continue }
            // Solo el primer aviso (el de hoy o el próximo) lleva el recuento: los demás se
            // recalculan al abrir la app y podrían quedar desfasados.
            let text: String
            if result.isEmpty {
                let titles = pending.prefix(3).map(\.title).joined(separator: ", ")
                text = pending.count == 1 ? "Tienes 1 tarea pendiente: \(titles)"
                    : "Tienes \(pending.count) tareas pendientes: \(titles)"
            } else {
                text = "Revisa tus tareas pendientes"
            }
            result.append(PlannedNotification(
                id: "homita.digest.\(dayKey(day, calendar: calendar))",
                kind: .taskDigest, title: "Tareas pendientes", body: text, fireDate: fire, link: .tareas
            ))
        }
        return result
    }

    // MARK: - Textos

    /// «Empieza ahora · 18:30», «Empieza en 15 min · 18:30 · Familia».
    static func body(lead minutes: Int, start: Date, timeZone: TimeZone, extra: String?) -> String {
        var parts = [leadText(minutes), timeText(start, timeZone: timeZone)]
        if let extra, !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: " · ")
    }

    static func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Empieza ahora"
        case 1..<60: return "Empieza en \(minutes) min"
        case 60..<1440:
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "Empieza en \(hours) h" : "Empieza en \(hours) h \(rest) min"
        default:
            let days = minutes / 1440
            return days == 1 ? "Empieza en 1 día" : "Empieza en \(days) días"
        }
    }

    static func timeText(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func personsText(_ persons: [PersonEntry]?) -> String? {
        guard let persons, !persons.isEmpty else { return nil }
        return persons.map(\.name).joined(separator: ", ")
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
