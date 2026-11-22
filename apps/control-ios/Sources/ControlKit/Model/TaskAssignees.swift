import Foundation

/// Regla de quién se puede asignar al crear una tarea (0038, P-1): solo personas con cuenta
/// (`app_user_id` no nulo) y con acceso a la lista (fila en `task_list_user`, cualquier rol).
/// Es la misma regla que aplica el servidor en `create_task`; la app solo la anticipa en el selector
/// y en el replay de la cola. Funciones puras.
///
/// Multi-hogar (R1-02): `GET person` trae personas de todos los hogares del usuario y una cuenta tiene
/// una persona por hogar. Se deduplica por hogar y cuenta (`home_id`, `app_user_id`): la misma cuenta
/// puede salir una vez por hogar, cada vez con la persona de ese hogar, y nunca se sustituye la de un
/// hogar por la de otro. Sin `home_id` (servidor anterior a 0038) cuenta como un hogar más.
///
/// Hogar de la lista (asignar-alta-lista): con `homeId` (el `home_id` de la lista) solo se ofrecen
/// las personas con ese mismo `home_id`; las de otros hogares (o sin hogar) no son asignables aunque
/// su cuenta esté en el ACL. Sin `homeId` (lista sin el campo) no se filtra por hogar.
public enum TaskAssignees {
    /// Personas asignables en una lista del servidor: con cuenta y con esa cuenta entre los miembros
    /// del ACL (`GET task-list/user`). Ofrece una opción por hogar y cuenta: si varias personas del
    /// mismo hogar comparten `app_user_id`, se conserva la primera en el orden de `persons`; las de
    /// hogares distintos se ofrecen todas (cada hogar, la suya). Con `homeId`, solo las de ese hogar.
    public static func assignable(persons: [PersonEntry], members: [MemberEntry], homeId: Int? = nil) -> [PersonEntry] {
        let accounts = Set(members.map(\.user_id))
        return unique(inHome(persons, homeId).filter { person in
            guard let account = person.app_user_id else { return false }
            return accounts.contains(account)
        })
    }

    /// Personas asignables en una lista creada offline (id < 0): aún no tiene ACL en el servidor y
    /// su único miembro será el creador como owner, así que solo es asignable la persona de su cuenta
    /// (una opción por hogar: la primera persona con esa cuenta de cada hogar, en el orden de `persons`).
    /// Con `homeId` (el hogar donde se crea la lista), solo la persona de ese hogar.
    public static func assignableInLocalList(persons: [PersonEntry], currentUserId: Int?, homeId: Int? = nil) -> [PersonEntry] {
        guard let currentUserId else { return [] }
        return unique(inHome(persons, homeId).filter { $0.app_user_id == currentUserId })
    }

    /// Separa `personIds` en las que siguen siendo asignables (`kept`) y las que no (`removed`),
    /// conservando el orden original. Un id que no está en `persons`, o que no es la persona que se
    /// ofrece para su hogar y cuenta, cuenta como no asignable. La persona válida de un hogar no se
    /// marca como quitada porque la misma cuenta tenga otra persona en otro hogar. Con `homeId`, un id
    /// de una persona de otro hogar cuenta como no asignable.
    public static func split(personIds: [Int], persons: [PersonEntry], members: [MemberEntry],
                             homeId: Int? = nil) -> (kept: [Int], removed: [Int]) {
        let allowed = Set(assignable(persons: persons, members: members, homeId: homeId).map(\.id))
        var kept: [Int] = []
        var removed: [Int] = []
        for id in personIds {
            if allowed.contains(id) { kept.append(id) } else { removed.append(id) }
        }
        return (kept, removed)
    }

    /// Selección podada a las personas asignables (al cambiar de lista en el editor). Conserva el
    /// orden de la selección y quita repetidos. Como `assignable` trae una persona por hogar y cuenta,
    /// la selección nunca queda con dos ids de la misma cuenta en el mismo hogar; las de hogares
    /// distintos se conservan cada una por su id (no se mezclan ni se sustituyen). El filtro de hogar
    /// ya viene aplicado en `assignable`: un id de otro hogar que no esté ahí se quita.
    public static func prune(selected: [Int], assignable: [PersonEntry]) -> [Int] {
        let allowed = Set(assignable.map(\.id))
        var seen = Set<Int>()
        return selected.filter { allowed.contains($0) && seen.insert($0).inserted }
    }

    /// Como `prune`, pero solo si hay roster de la lista (`rosterLoaded`). Sin él `assignable` es `[]`
    /// por falta de datos, no por regla: se conserva la selección tal cual (R1-03, edición sin conexión
    /// de una tarea local) y decide el servidor o la escalera del replay.
    public static func prune(selected: [Int], assignable: [PersonEntry], rosterLoaded: Bool) -> [Int] {
        rosterLoaded ? prune(selected: selected, assignable: assignable) : selected
    }

    /// Personas del hogar `homeId` (igualdad estricta de `home_id`); todas si `homeId` es nil.
    private static func inHome(_ persons: [PersonEntry], _ homeId: Int?) -> [PersonEntry] {
        guard let homeId else { return persons }
        return persons.filter { $0.home_id == homeId }
    }

    /// Clave de deduplicación: hogar (`nil` si el servidor no lo envía) y cuenta.
    private struct HomeAccount: Hashable {
        let home: Int?
        let account: Int
    }

    /// Deja una persona por hogar y cuenta (`home_id`, `app_user_id`) conservando la primera
    /// aparición. Se llama siempre con personas ya filtradas con cuenta; las que no tienen cuenta se
    /// descartan.
    private static func unique(_ persons: [PersonEntry]) -> [PersonEntry] {
        var seen = Set<HomeAccount>()
        return persons.filter { person in
            guard let account = person.app_user_id else { return false }
            return seen.insert(HomeAccount(home: person.home_id, account: account)).inserted
        }
    }
}
