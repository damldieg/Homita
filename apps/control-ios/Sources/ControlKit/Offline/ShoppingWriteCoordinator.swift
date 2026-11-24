import Foundation

/// Decide si una escritura de la Compra se envía o se encola (mismo patrón que `TaskWriteCoordinator`,
/// D-024): se encola sin intentar si la cola del hogar no está vacía (FIFO) o no hay red; si se envía
/// y falla por red, se encola la misma op (mismo `client_request_id`). Un 5xx o un 4xx en línea se
/// lanzan para que el store los muestre; el reintento debe reusar la misma op para no duplicar.
@MainActor
public struct ShoppingWriteCoordinator {
    public typealias Outcome = TaskWriteCoordinator.Outcome

    public let outbox: OutboxStore
    private let repo: ShoppingRepository
    private let isOnline: @MainActor () -> Bool

    public init(outbox: OutboxStore, shopping: ShoppingRepository,
                isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline }) {
        self.outbox = outbox
        self.repo = shopping
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
            return .sent(remoteId: try await OutboxSender.sendShopping(op, idMap: outbox.idMap, repo: repo))
        } catch OutboxSender.SendError.unresolvedRef {
            outbox.enqueue(op)
            return .queued
        } catch APIError.network {
            outbox.enqueue(op)
            return .queued
        }
    }
}
