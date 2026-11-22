import Foundation

/// Envío de una op al servidor, compartido por el replayer y `TaskWriteCoordinator`. Los creates
/// llevan `client_request_id` = `op.id` (0035): reenviarlos no duplica.
struct OutboxSender {
    let tasks: TaskRepository
    let taskLists: TaskListRepository

    /// Una referencia temporal sin ID real (su create se descartó o aún no se confirmó).
    enum SendError: Error, Equatable {
        case unresolvedRef
    }

    /// Envía la op y devuelve el ID real creado (solo en los creates).
    func send(_ op: PendingOp, idMap: [Int: Int]) async throws -> Int? {
        func id(_ ref: Ref) throws -> Int {
            guard let id = ref.resolved(with: idMap) else { throw SendError.unresolvedRef }
            return id
        }
        switch op.kind {
        case .createTask(_, let listRef, let title, let personIds, let priority):
            let request = CreateTaskRequest(task_list_id: try id(listRef), title: title, person_ids: personIds,
                                            client_request_id: op.clientRequestId, priority: priority)
            return try await tasks.create(request).id
        case .updateTask(let ref, _, let title, let personIds, let priority):
            _ = try await tasks.update(UpdateTaskRequest(id: try id(ref), title: title, person_ids: personIds, priority: priority))
        case .completeTask(let ref, _, let completed):
            _ = try await tasks.complete(CompleteTaskRequest(id: try id(ref), completed: completed))
        case .deleteTask(let ref, _):
            try await tasks.delete(id: try id(ref))
        case .createList(_, let name, let color, let sort, let widget, let dashboard):
            let request = CreateTaskListRequest(name: name, color: color, sort: sort, widget: widget, dashboard: dashboard, client_request_id: op.clientRequestId)
            return try await taskLists.create(request).id
        case .updateList(let ref, let name, let color, let sort, let widget, let dashboard):
            _ = try await taskLists.update(UpdateTaskListRequest(id: try id(ref), name: name, color: color, sort: sort, widget: widget, dashboard: dashboard))
        case .deleteList(let ref):
            try await taskLists.delete(id: try id(ref))
        }
        return nil
    }
}

/// Resultado de una pasada del replayer.
public struct ReplaySummary: Equatable, Sendable {
    /// Por qué paró: cola vacía, sin red, error reintentable (red o 5xx), sesión caducada o cancelado.
    public enum Stop: Equatable, Sendable {
        case drained, offline, retryable, sessionExpired, cancelled
    }

    public var acked = 0
    public var discarded = 0
    public var stop: Stop = .drained
}

/// Reproduce la cola de un hogar en orden FIFO (D-024). Vuelo único por cola: la pasada en curso se
/// guarda en la propia `OutboxStore` (no en el replayer), así que una segunda llamada mientras hay otra
/// en curso espera a la misma pasada aunque venga de otro replayer (UI y `BackgroundRefresh`, R1-02). Para en el primer error de red o 5xx (la op
/// y el resto se conservan, Q11) y en una sesión caducada (se conserva todo, R1); los 4xx descartan
/// la op con sus dependientes y dejan un aviso. Excepción (0038, P-4 b): un 400 `Invalid person` en
/// un create de tarea con personas no descarta la op; se reescribe con las personas que siguen siendo
/// asignables según el roster fresco (y, si el servidor vuelve a rechazarla, sin personas), se reenvía
/// con la misma clave y se confirma con un aviso. Se cancela de forma cooperativa entre ops.
@MainActor
public final class OutboxReplayer {
    private let sender: OutboxSender
    private let taskLists: TaskListRepository
    private let persons: PersonRepository?
    private let isOnline: @MainActor () -> Bool

    /// `persons` habilita la reasignación de P-4; sin él, un `Invalid person` descarta como cualquier 4xx.
    public init(tasks: TaskRepository, taskLists: TaskListRepository, persons: PersonRepository? = nil,
                isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline }) {
        self.sender = OutboxSender(tasks: tasks, taskLists: taskLists)
        self.taskLists = taskLists
        self.persons = persons
        self.isOnline = isOnline
    }

    /// Qué hacer con una op ante un error, en el orden del plan (R5: «no existe» antes que 5xx).
    enum Disposition: Equatable {
        /// Cuenta como confirmada (delete de algo que ya no existe; respuesta ilegible tras un 2xx).
        case ack
        /// Se descarta con aviso; `cascade` arrastra las ops del mismo recurso.
        case discard(cascade: Bool)
        /// Sesión caducada: para y conserva todo.
        case pause
        /// Red o 5xx: para, conserva y suma un intento.
        case retry
    }

    static func disposition(for error: APIError, kind: PendingOp.Kind) -> Disposition {
        if error.isNotFound { return kind.isDelete ? .ack : .discard(cascade: true) }
        switch error {
        case .sessionExpired:
            return .pause
        case .http(let status, _) where status == 401:
            return .pause
        case .http(let status, _) where (400...499).contains(status):
            return .discard(cascade: false)
        case .decoding:
            // Un create es idempotente: se reenvía con la misma clave para conocer el ID real.
            return kind.isCreate ? .retry : .ack
        case .network, .http:
            return .retry
        }
    }

    /// Reproduce la cola. Si ya hay una pasada en curso para esta cola (de este u otro replayer),
    /// espera a esa.
    @discardableResult
    public func replay(_ outbox: OutboxStore) async -> ReplaySummary {
        let task: Task<ReplaySummary, Never>
        if let current = outbox.replayTask {
            task = current
        } else {
            task = Task { await self.drain(outbox) }
            outbox.replayTask = task
        }
        let summary = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if outbox.replayTask == task { outbox.replayTask = nil }
        return summary
    }

    private func drain(_ outbox: OutboxStore) async -> ReplaySummary {
        var summary = ReplaySummary()
        while let op = outbox.ops.first {
            if Task.isCancelled {
                summary.stop = .cancelled
                return summary
            }
            guard isOnline() else {
                summary.stop = .offline
                return summary
            }
            outbox.beginFlight(op.id)
            do {
                let remoteId = try await sender.send(op, idMap: outbox.idMap)
                outbox.ack(op.id, remoteId: remoteId)
                summary.acked += 1
            } catch let error as APIError where persons != nil && Self.isInvalidPerson(error) && Self.assignedPersons(op.kind) != nil {
                if let stop = await reassign(op, in: outbox, summary: &summary) {
                    summary.stop = stop
                    return summary
                }
            } catch {
                if let stop = Self.handle(error, op: op, in: outbox, summary: &summary) {
                    summary.stop = stop
                    return summary
                }
            }
        }
        summary.stop = .drained
        return summary
    }

    /// Aplica la disposición de un error a la op. Devuelve el motivo de parada o nil para seguir.
    private static func handle(_ error: Error, op: PendingOp, in outbox: OutboxStore, summary: inout ReplaySummary) -> ReplaySummary.Stop? {
        if let sendError = error as? OutboxSender.SendError, sendError == .unresolvedRef {
            // Su create ya no está (se descartó): no hay nada que enviar.
            outbox.discard(op.id, dependents: target(of: op.kind).map { [$0] } ?? [])
            summary.discarded += 1
            return nil
        }
        guard let error = error as? APIError else {
            outbox.endFlight()
            outbox.recordAttempt(op.id)
            return .retryable
        }
        switch disposition(for: error, kind: op.kind) {
        case .ack:
            outbox.ack(op.id)
            summary.acked += 1
            return nil
        case .discard(let cascade):
            let dependents = cascade ? (target(of: op.kind).map { [$0] } ?? []) : []
            outbox.discard(op.id, dependents: dependents, notice: notice(for: op.kind, error: error))
            summary.discarded += 1
            return nil
        case .pause:
            outbox.endFlight()
            return .sessionExpired
        case .retry:
            outbox.endFlight()
            outbox.recordAttempt(op.id)
            return .retryable
        }
    }

    // MARK: - 0038: personas sin acceso al reproducir (P-4 b)

    /// 400 `Invalid person` (0038): alguna persona no tiene cuenta o acceso a la lista.
    static func isInvalidPerson(_ error: APIError) -> Bool {
        if case .http(400, "Invalid person") = error { return true }
        return false
    }

    /// Personas de un create de tarea; nil si no es un create de tarea o no lleva personas.
    static func assignedPersons(_ kind: PendingOp.Kind) -> [Int]? {
        guard case .createTask(_, _, _, let personIds?, _) = kind, !personIds.isEmpty else { return nil }
        return personIds
    }

    /// Misma op con otras personas (nil o vacío = sin la clave). Conserva temporal, lista, título y prioridad.
    static func replacingPersons(_ kind: PendingOp.Kind, with personIds: [Int]?) -> PendingOp.Kind {
        guard case .createTask(let local, let listRef, let title, _, let priority) = kind else { return kind }
        return .createTask(local: local, listRef: listRef, title: title,
                           personIds: personIds?.isEmpty == true ? nil : personIds, priority: priority)
    }

    /// Escalera de P-4 para un create rechazado por `Invalid person`: roster fresco (`GET person` y
    /// `GET task-list/user`), reenvío con las asignables y, si se vuelve a rechazar, sin personas. La op
    /// reescrita se guarda en disco antes de cada reenvío; la clave es la misma porque el 400 no deja
    /// fila en `client_request`. La tarea nunca se descarta por las personas. Devuelve el motivo de
    /// parada o nil para seguir con la cola.
    private func reassign(_ op: PendingOp, in outbox: OutboxStore, summary: inout ReplaySummary) async -> ReplaySummary.Stop? {
        guard let persons, let original = Self.assignedPersons(op.kind),
              case .createTask(_, let listRef, let title, _, _) = op.kind,
              let listId = listRef.resolved(with: outbox.idMap) else {
            return Self.handle(APIError.http(status: 400, message: "Invalid person"), op: op, in: outbox, summary: &summary)
        }
        // Roster fresco. Red o 5xx: se conserva la op y se reintenta; sesión caducada: pausa. Otro
        // 4xx (p. ej. la lista ya no es visible): sin roster, se pasa al último escalón.
        var roster: [PersonEntry] = []
        var kept: [Int] = []
        do {
            roster = try await persons.index()
            let members = try await taskLists.users(taskListId: listId)
            kept = TaskAssignees.split(personIds: original, persons: roster, members: members).kept
        } catch let error as APIError {
            switch Self.disposition(for: error, kind: op.kind) {
            case .pause, .retry:
                return Self.handle(error, op: op, in: outbox, summary: &summary)
            case .ack, .discard:
                kept = []
            }
        } catch {
            return Self.handle(error, op: op, in: outbox, summary: &summary)
        }
        // Escalones: las asignables (si cambian algo) y, como último, ninguna.
        var steps: [[Int]] = []
        if !kept.isEmpty && kept != original { steps.append(kept) }
        steps.append([])
        var current = op
        for (index, step) in steps.enumerated() {
            current.kind = Self.replacingPersons(op.kind, with: step)
            outbox.replaceKind(op.id, with: current.kind)
            do {
                let remoteId = try await sender.send(current, idMap: outbox.idMap)
                let removed = original.filter { !step.contains($0) }
                let names = removed.compactMap { id in roster.first { $0.id == id }?.name }
                outbox.ack(op.id, remoteId: remoteId, notice: Self.assigneeNotice(title: title, removedNames: names))
                summary.acked += 1
                return nil
            } catch let error as APIError where Self.isInvalidPerson(error) && index < steps.count - 1 {
                continue
            } catch {
                return Self.handle(error, op: current, in: outbox, summary: &summary)
            }
        }
        return nil
    }

    /// Aviso de una tarea confirmada sin alguna persona asignada (0038). Sin nombres conocidos, «una persona».
    static func assigneeNotice(title: String, removedNames: [String]) -> String {
        guard !removedNames.isEmpty else {
            return "«\(title)» se sincronizó sin asignar a una persona: ya no tiene acceso a la lista."
        }
        let names: String
        if removedNames.count == 1 {
            names = removedNames[0]
        } else {
            names = removedNames.dropLast().joined(separator: ", ") + " y " + removedNames[removedNames.count - 1]
        }
        let verb = removedNames.count == 1 ? "tiene" : "tienen"
        return "«\(title)» se sincronizó sin asignar a \(names): ya no \(verb) acceso a la lista."
    }

    /// Recurso del que dependen las ops posteriores (los creates ya arrastran su temporal).
    private static func target(of kind: PendingOp.Kind) -> Ref? {
        if kind.isCreate { return nil }
        return kind.taskRef ?? kind.listRef
    }

    /// Texto del aviso de descarte.
    static func notice(for kind: PendingOp.Kind, error: APIError) -> String {
        let what = kind.subject.map { "No se pudo sincronizar \($0)" } ?? "No se pudo sincronizar un cambio pendiente"
        if error.isNotFound { return "\(what): ya no existe." }
        return "\(what). \(error.writeMessage)"
    }
}
