import Foundation

/// Ítem de Inicio abierto en la hoja de edición (evento, tarea o rutina).
/// El id lleva prefijo por tipo para que un evento 5 y una tarea 5 no coincidan.
enum InicioItem: Identifiable, Equatable {
    case event(EventEntry)
    case task(TaskEntry)
    case routine(RoutineEntry)

    enum Kind: Equatable { case event, task, routine }

    var kind: Kind {
        switch self {
        case .event: return .event
        case .task: return .task
        case .routine: return .routine
        }
    }

    var id: String {
        switch self {
        case .event(let event): return "event-\(event.id)"
        case .task(let task): return "task-\(task.id)"
        case .routine(let routine): return "routine-\(routine.id)"
        }
    }
}
