import Foundation
import HomitaShared

/// Construye el `HomitaSnapshot` (lo que ven widgets y Live Activity) con los datos de Inicio.
public enum SnapshotBuilder {
    /// Pendientes que se guardan para los widgets.
    public static let taskLimit = 5

    public static func build(
        events: [EventEntry], routines: [RoutineEntry], tasks: [TaskEntry],
        homeName: String?, now: Date, timeZone: TimeZone = .current
    ) -> HomitaSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayRoutines = TodaySummary.routines(routines, on: now, timeZone: timeZone)
        let timed = todayRoutines.compactMap { routine -> HomitaSnapshot.Routine? in
            guard let start = RoutineStatus.startToday(time: routine.time, now: now, timeZone: timeZone) else { return nil }
            return snapshotRoutine(routine, start: start)
        }
        let untimed = todayRoutines.compactMap { routine -> HomitaSnapshot.Routine? in
            RoutineStatus.startToday(time: routine.time, now: now, timeZone: timeZone) == nil
                ? snapshotRoutine(routine, start: nil) : nil
        }
        let todayEvents = TodaySummary.events(events.filter { $0.routine_id == nil }, on: now, timeZone: timeZone)
            .compactMap { event -> HomitaSnapshot.Event? in
                guard let start = PHPDateTime.parse(event.date_at, timeZone: timeZone) else { return nil }
                return HomitaSnapshot.Event(
                    id: event.id, title: event.title, colorHex: event.calendar_color ?? Palette.fallbackItem, start: start
                )
            }
        let pending = TodaySummary.pendingTasks(tasks, limit: tasks.count)
        return HomitaSnapshot(
            generatedAt: now, dayStart: calendar.startOfDay(for: now), homeName: homeName, signedIn: true,
            routines: timed + untimed, events: todayEvents, pendingTaskCount: pending.count,
            tasks: pending.prefix(taskLimit).map {
                HomitaSnapshot.TaskItem(
                    id: $0.id, title: $0.title, listName: $0.task_list_name ?? "Tareas",
                    colorHex: $0.task_list_color ?? Palette.accentHex
                )
            }
        )
    }

    private static func snapshotRoutine(_ routine: RoutineEntry, start: Date?) -> HomitaSnapshot.Routine {
        HomitaSnapshot.Routine(
            id: routine.id, title: routine.title, colorHex: routine.calendar_color ?? Palette.fallbackItem,
            start: start, persons: (routine.persons ?? []).map(\.name)
        )
    }
}
