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
                guard let due = date(task.due_at), due > now,
                      isMine(task, roster: roster, currentUserId: currentUserId) else { return nil }
                return (task, due)
            }
            .min { $0.due < $1.due }
    }
}
