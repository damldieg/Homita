import Foundation

/// Decide si una escritura de tareas o listas se envía o se encola (D-024, online-first con caída
/// a la cola). Se encola sin intentar si la cola del hogar no está vacía (mantiene el FIFO, R8) o
/// no hay red; si se envía y falla por red, se encola la misma op (mismo `client_request_id`). Un
/// 5xx o un 4xx en línea se lanzan para que el store muestre el toast de siempre; el reintento debe
/// reusar la misma op para no duplicar.
@MainActor
public struct TaskWriteCoordinator {
    public enum Outcome: Equatable {
        /// Enviada; `remoteId` es el ID real en los creates.
        case sent(remoteId: Int?)
        /// En la cola: cuenta como éxito para la UI.
        case queued
    }

    public let outbox: OutboxStore
    private let sender: OutboxSender
    private let isOnline: @MainActor () -> Bool

    public init(outbox: OutboxStore, tasks: TaskRepository, taskLists: TaskListRepository,
                isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline }) {
        self.outbox = outbox
        self.sender = OutboxSender(tasks: tasks, taskLists: taskLists)
        self.isOnline = isOnline
    }

    /// Op del hogar de la cola. Crear la op fuera del cierre de reintento conserva su `id`.
    public func makeOp(_ kind: PendingOp.Kind, id: UUID = UUID()) -> PendingOp {
        PendingOp(id: id, homeId: outbox.homeId, kind: kind)
    }

    /// Envía o encola. Lanza los errores que no son de red (5xx, 4xx, sesión, decodificación).
    @discardableResult
    public func perform(_ op: PendingOp) async throws -> Outcome {
        guard outbox.isEmpty, isOnline() else {
            outbox.enqueue(op)
            return .queued
        }
        do {
            return .sent(remoteId: try await sender.send(op, idMap: outbox.idMap))
        } catch OutboxSender.SendError.unresolvedRef {
            outbox.enqueue(op)
            return .queued
        } catch APIError.network {
            outbox.enqueue(op)
            return .queued
        }
    }
}
