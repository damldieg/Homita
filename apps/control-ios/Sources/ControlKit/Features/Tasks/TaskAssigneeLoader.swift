import Foundation
import Observation

/// Cargador compartido de las personas asignables al crear una tarea (0038): personas del hogar
/// (`GET person`) y miembros del ACL de cada lista (`GET task-list/user`). Lo usan `TasksStore` e
/// `InicioStore` para el selector de las altas; la regla vive en `TaskAssignees`. Solo se ofrecen
/// personas del mismo hogar que la lista (`homeId`).
@MainActor
@Observable
public final class TaskAssigneeLoader {
    /// Personas del hogar (todas; el filtro se aplica en `assignable`).
    public private(set) var persons: [PersonEntry] = []
    /// Miembros del ACL por id real de lista.
    public private(set) var membersByList: [Int: [MemberEntry]] = [:]
    /// Destino de los errores de lectura (lo fija el store: alerta de la pantalla).
    @ObservationIgnored public var onError: @MainActor (Error) -> Void = { _ in }
    /// Si `GET person` ya respondió (aunque fuera con una lista vacía).
    @ObservationIgnored private var personsLoaded = false

    @ObservationIgnored private let personsRepo: PersonRepository?
    @ObservationIgnored private let taskListsRepo: TaskListRepository
    @ObservationIgnored private let outbox: OutboxStore?

    public init(persons: PersonRepository?, taskLists: TaskListRepository, outbox: OutboxStore? = nil) {
        self.personsRepo = persons
        self.taskListsRepo = taskLists
        self.outbox = outbox
    }

    /// ID real de un temporal ya confirmado; el mismo ID si es remoto o aún no se resolvió.
    private func resolve(_ id: Int) -> Int {
        outbox?.resolve(id) ?? id
    }

    /// Carga las personas (si aún no están) y los miembros de la lista. Una lista local (id < 0 sin
    /// resolver) no tiene ACL en el servidor: solo se cargan las personas. Devuelve `hasRoster`.
    @discardableResult
    public func load(listId: Int) async -> Bool {
        if !personsLoaded, let personsRepo {
            do {
                persons = try await personsRepo.index()
                personsLoaded = true
            } catch {
                onError(error)
            }
        }
        let id = resolve(listId)
        if id > 0 {
            do {
                membersByList[id] = try await taskListsRepo.users(taskListId: id)
            } catch {
                onError(error)
            }
        }
        return hasRoster(listId: listId)
    }

    /// Si hay datos para decidir quién es asignable en `listId`: personas cargadas y, en una lista
    /// remota, sus miembros. Sin ellos `assignable` devuelve `[]` y podar vaciaría la selección (R1-03).
    public func hasRoster(listId: Int) -> Bool {
        let id = resolve(listId)
        return personsLoaded && (id < 0 || membersByList[id] != nil)
    }

    /// Personas asignables al crear en `listId`. En una lista local, solo la de `currentUserId`; en
    /// una remota cuyos miembros aún no se cargaron, ninguna (la vista llama antes a `load`).
    /// `homeId` es el hogar de la lista (`home_id`; en una local, el hogar activo): solo se ofrecen
    /// personas de ese hogar. `nil` no filtra por hogar.
    public func assignable(listId: Int, currentUserId: Int?, homeId: Int? = nil) -> [PersonEntry] {
        let id = resolve(listId)
        guard id > 0 else {
            return TaskAssignees.assignableInLocalList(persons: persons, currentUserId: currentUserId, homeId: homeId)
        }
        return TaskAssignees.assignable(persons: persons, members: membersByList[id] ?? [], homeId: homeId)
    }

    /// Hogar de `listId` según `lists` (por id resuelto); si la lista no lo trae (local o caché
    /// antigua), `fallbackHomeId` (el hogar activo de la cola, donde se ven y se crean las listas).
    public func homeId(listId: Int, lists: [TaskListEntry], fallbackHomeId: Int?) -> Int? {
        let id = resolve(listId)
        return lists.first { $0.id == id }?.home_id ?? fallbackHomeId
    }
}
