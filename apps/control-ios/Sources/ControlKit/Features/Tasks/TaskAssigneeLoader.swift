import Foundation
import Observation

/// Cargador compartido de las personas asignables al crear una tarea (0038): personas del hogar
/// (`GET person`) y miembros del ACL de cada lista (`GET task-list/user`). Lo usan `TasksStore` e
/// `InicioStore` para el selector de las altas; la regla vive en `TaskAssignees`.
@MainActor
@Observable
public final class TaskAssigneeLoader {
    /// Personas del hogar (todas; el filtro se aplica en `assignable`).
    public private(set) var persons: [PersonEntry] = []
    /// Miembros del ACL por id real de lista.
    public private(set) var membersByList: [Int: [MemberEntry]] = [:]
    /// Destino de los errores de lectura (lo fija el store: alerta de la pantalla).
    @ObservationIgnored public var onError: @MainActor (Error) -> Void = { _ in }

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
    /// resolver) no tiene ACL en el servidor: solo se cargan las personas.
    public func load(listId: Int) async {
        if persons.isEmpty, let personsRepo {
            do {
                persons = try await personsRepo.index()
            } catch {
                onError(error)
            }
        }
        let id = resolve(listId)
        guard id > 0 else { return }
        do {
            membersByList[id] = try await taskListsRepo.users(taskListId: id)
        } catch {
            onError(error)
        }
    }

    /// Personas asignables al crear en `listId`. En una lista local, solo la de `currentUserId`; en
    /// una remota cuyos miembros aún no se cargaron, ninguna (la vista llama antes a `load`).
    public func assignable(listId: Int, currentUserId: Int?) -> [PersonEntry] {
        let id = resolve(listId)
        guard id > 0 else {
            return TaskAssignees.assignableInLocalList(persons: persons, currentUserId: currentUserId)
        }
        return TaskAssignees.assignable(persons: persons, members: membersByList[id] ?? [])
    }
}
