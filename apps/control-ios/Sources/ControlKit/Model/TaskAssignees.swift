import Foundation

/// Regla de quién se puede asignar al crear una tarea (0038, P-1): solo personas con cuenta
/// (`app_user_id` no nulo) y con acceso a la lista (fila en `task_list_user`, cualquier rol).
/// Es la misma regla que aplica el servidor en `create_task`; la app solo la anticipa en el selector
/// y en el replay de la cola. Funciones puras.
public enum TaskAssignees {
    /// Personas asignables en una lista del servidor: con cuenta y con esa cuenta entre los miembros
    /// del ACL (`GET task-list/user`). Conserva el orden de `persons` y no repite personas.
    public static func assignable(persons: [PersonEntry], members: [MemberEntry]) -> [PersonEntry] {
        let accounts = Set(members.map(\.user_id))
        return unique(persons.filter { person in
            guard let account = person.app_user_id else { return false }
            return accounts.contains(account)
        })
    }

    /// Personas asignables en una lista creada offline (id < 0): aún no tiene ACL en el servidor y
    /// su único miembro será el creador como owner, así que solo es asignable la persona de su cuenta.
    public static func assignableInLocalList(persons: [PersonEntry], currentUserId: Int?) -> [PersonEntry] {
        guard let currentUserId else { return [] }
        return unique(persons.filter { $0.app_user_id == currentUserId })
    }

    /// Separa `personIds` en las que siguen siendo asignables (`kept`) y las que no (`removed`),
    /// conservando el orden original. Un id que no está en `persons` cuenta como no asignable.
    public static func split(personIds: [Int], persons: [PersonEntry], members: [MemberEntry]) -> (kept: [Int], removed: [Int]) {
        let allowed = Set(assignable(persons: persons, members: members).map(\.id))
        var kept: [Int] = []
        var removed: [Int] = []
        for id in personIds {
            if allowed.contains(id) { kept.append(id) } else { removed.append(id) }
        }
        return (kept, removed)
    }

    /// Selección podada a las personas asignables (al cambiar de lista en el editor). Conserva el
    /// orden de la selección y quita repetidos.
    public static func prune(selected: [Int], assignable: [PersonEntry]) -> [Int] {
        let allowed = Set(assignable.map(\.id))
        var seen = Set<Int>()
        return selected.filter { allowed.contains($0) && seen.insert($0).inserted }
    }

    /// Quita personas repetidas (mismo id) conservando la primera aparición.
    private static func unique(_ persons: [PersonEntry]) -> [PersonEntry] {
        var seen = Set<Int>()
        return persons.filter { seen.insert($0.id).inserted }
    }
}
