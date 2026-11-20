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
        case .createTask(_, let listRef, let title, let personIds):
            let request = CreateTaskRequest(task_list_id: try id(listRef), title: title, person_ids: personIds, client_request_id: op.clientRequestId)
            return try await tasks.create(request).id
        case .updateTask(let ref, _, let title, let personIds):
            _ = try await tasks.update(UpdateTaskRequest(id: try id(ref), title: title, person_ids: personIds))
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
/// la op con sus dependientes y dejan un aviso. Se cancela de forma cooperativa entre ops.
@MainActor
public final class OutboxReplayer {
    private let sender: OutboxSender
    private let isOnline: @MainActor () -> Bool

    public init(tasks: TaskRepository, taskLists: TaskListRepository,
                isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline }) {
        self.sender = OutboxSender(tasks: tasks, taskLists: taskLists)
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
            } catch OutboxSender.SendError.unresolvedRef {
                // Su create ya no está (se descartó): no hay nada que enviar.
                outbox.discard(op.id, dependents: Self.target(of: op.kind).map { [$0] } ?? [])
                summary.discarded += 1
            } catch let error as APIError {
                switch Self.disposition(for: error, kind: op.kind) {
                case .ack:
                    outbox.ack(op.id)
                    summary.acked += 1
                case .discard(let cascade):
                    let dependents = cascade ? (Self.target(of: op.kind).map { [$0] } ?? []) : []
                    outbox.discard(op.id, dependents: dependents, notice: Self.notice(for: op.kind, error: error))
                    summary.discarded += 1
                case .pause:
                    outbox.endFlight()
                    summary.stop = .sessionExpired
                    return summary
                case .retry:
                    outbox.endFlight()
                    outbox.recordAttempt(op.id)
                    summary.stop = .retryable
                    return summary
                }
            } catch {
                outbox.endFlight()
                outbox.recordAttempt(op.id)
                summary.stop = .retryable
                return summary
            }
        }
        summary.stop = .drained
        return summary
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
