import Foundation

/// Fecha límite de una tarea (0041, fecha-limite-vencimiento). El servidor guarda `YYYY-MM-DD HH:MM:SS`
/// en UTC naive; aquí se convierte a `Date` y al revés. Funciones puras, sin estado.
public enum TaskDue {
    private static let utc = TimeZone(identifier: "UTC") ?? .current

    /// Antelación del banner de Inicio: solo se muestran vencimientos futuros.
    public static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return PHPDateTime.parse(raw, timeZone: utc)
    }

    /// Texto para el servidor (UTC, `YYYY-MM-DD HH:MM:SS`).
    public static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Pendientes de prioridad alta de esta cuenta: las suyas y las del hogar sin asignar (sin completar).
    public static func highPriorityForMe(_ tasks: [TaskEntry], roster: [PersonEntry], currentUserId: Int?) -> [TaskEntry] {
        tasks.filter { !$0.isCompleted && $0.priorityValue == .alta && isMine($0, roster: roster, currentUserId: currentUserId) }
    }

    /// Agrupa tareas por lista: orden por nombre de lista (desempate por id) y, dentro de cada lista, por título.
    /// Un nombre vacío o ausente se muestra como «Tareas», igual que en la tarjeta de Inicio.
    public static func groupedByList(_ tasks: [TaskEntry]) -> [TaskListGroup] {
        Dictionary(grouping: tasks, by: \.task_list_id)
            .map { id, items in
                let name = items.first?.task_list_name.flatMap { $0.isEmpty ? nil : $0 } ?? "Tareas"
                return TaskListGroup(id: id, name: name, colorHex: items.first?.task_list_color,
                                     tasks: items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }

    /// Texto y enlace del contador de prioridad alta del resumen (AC2: sin tareas, sin «Ver más»).
    public static func highPrioritySummary(count: Int) -> (text: String, showsLink: Bool) {
        count == 0 ? ("Sin tareas de prioridad alta", false) : ("\(count) de prioridad alta", true)
    }

    /// ¿La tarea es para esta cuenta? Sin personas (o sin datos) cuenta como sin asignar; si tiene
    /// personas, debe haber alguna vinculada a `currentUserId` en `roster`.
    public static func isMine(_ task: TaskEntry, roster: [PersonEntry], currentUserId: Int?) -> Bool {
        let assigned = task.persons ?? []
        if assigned.isEmpty { return true }
        guard let currentUserId else { return false }
        let mine = Set(roster.filter { $0.app_user_id == currentUserId }.map(\.id))
        return assigned.contains { mine.contains($0.id) }
    }

    /// Tarea que destaca el banner de Inicio: la de vencimiento más próximo entre las pendientes de
    /// prioridad alta, con fecha futura, mías o sin asignar y no cerradas en esta sesión.
    public static func banner(
        tasks: [TaskEntry], now: Date, roster: [PersonEntry], currentUserId: Int?, dismissed: Set<Int>
    ) -> (task: TaskEntry, due: Date)? {
        tasks
            .filter { !$0.isCompleted && $0.priorityValue == .alta && !dismissed.contains($0.id) }
            .compactMap { task -> (task: TaskEntry, due: Date)? in
                // Banner solo en las 24 h previas al vencimiento; antes no aparece.
                guard let due = date(task.due_at), due > now, due <= now.addingTimeInterval(24 * 3600),
                      isMine(task, roster: roster, currentUserId: currentUserId) else { return nil }
                return (task, due)
            }
            .min { $0.due < $1.due }
    }
}

/// Lista con sus tareas de prioridad alta pendientes (resumen de Inicio, 0042-UI).
public struct TaskListGroup: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let colorHex: String?
    public let tasks: [TaskEntry]
}
