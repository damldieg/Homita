import Foundation

/// Escritura de tareas, listas o artículos de la Compra pendiente de enviar (cola offline, D-024). `id` es también el
/// `client_request_id` de los creates, así un reenvío no duplica en el servidor (0035).
public struct PendingOp: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    /// Hogar activo cuando se encoló (la cola es por hogar; solo se reproduce la del activo).
    public let homeId: String
    /// Intentos fallidos por red o 5xx (diagnóstico; no hay descarte automático, A7).
    public var attempts: Int
    public var kind: Kind
    /// Personas quitadas por el replay (0038, P-4 b) cuyo aviso sigue pendiente: lo emite el ack que
    /// confirme la op, aunque llegue en otra pasada tras un reintento. nil = sin aviso; `[]` = aviso
    /// sin nombres conocidos («una persona»). Opcional en disco: las colas antiguas siguen leyéndose.
    public var removedAssignees: [String]?

    /// Operación. Las de tarea guardan su `listRef`: hace falta para anularlas al borrar la lista.
    /// `priority` (0037) es opcional: nil = no se envía (create → `media`, update → conserva). El
    /// Codable sintetizado la decodifica con `decodeIfPresent`, así las ops ya encoladas sin la clave
    /// siguen leyéndose (fijado en PendingOpTests).
    public enum Kind: Codable, Equatable, Sendable {
        case createTask(local: Int, listRef: Ref, title: String, personIds: [Int]?, priority: String? = nil, dueAt: String? = nil)
        case updateTask(ref: Ref, listRef: Ref, title: String, personIds: [Int]?, priority: String? = nil, dueAt: String? = nil)
        case completeTask(ref: Ref, listRef: Ref, completed: Bool)
        case deleteTask(ref: Ref, listRef: Ref)
        case createList(local: Int, name: String, color: String, sort: String, widget: Bool, dashboard: Bool)
        case updateList(ref: Ref, name: String, color: String, sort: String, widget: Bool, dashboard: Bool)
        case deleteList(ref: Ref)
        /// Alta a mano en la Compra. `state` permite fundir en el alta un marcar posterior (el endpoint
        /// de alta no recibe estado: el replay lo fija tras crear, con la misma clave de idempotencia).
        case createShoppingItem(local: Int, label: String?, quantity: Double?, unit: String, section: String?, foodId: Int64?,
                                state: String = ShoppingState.pending)
        case checkShoppingItem(ref: Ref)
        case uncheckShoppingItem(ref: Ref)
        /// «Ya lo tengo».
        case haveShoppingItem(ref: Ref)
    }

    public init(id: UUID = UUID(), createdAt: Date = Date(), homeId: String, attempts: Int = 0, kind: Kind,
                removedAssignees: [String]? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.homeId = homeId
        self.attempts = attempts
        self.kind = kind
        self.removedAssignees = removedAssignees
    }

    /// `client_request_id` que viaja en los creates (UUID en minúsculas).
    public var clientRequestId: String { id.uuidString.lowercased() }
}

extension PendingOp.Kind {
    /// Recurso de tarea sobre el que actúa (el temporal en un create); nil en las de lista.
    var taskRef: Ref? {
        switch self {
        case .createTask(let local, _, _, _, _, _): return .local(local)
        case .updateTask(let ref, _, _, _, _, _), .completeTask(let ref, _, _), .deleteTask(let ref, _): return ref
        default: return nil
        }
    }

    /// Artículo de la Compra sobre el que actúa (el temporal en un alta); nil en las demás.
    var shoppingRef: Ref? {
        switch self {
        case .createShoppingItem(let local, _, _, _, _, _, _): return .local(local)
        case .checkShoppingItem(let ref), .uncheckShoppingItem(let ref), .haveShoppingItem(let ref): return ref
        default: return nil
        }
    }

    /// Estado de la Compra que fija una op de marcar; nil en las demás.
    var shoppingState: String? {
        switch self {
        case .checkShoppingItem: return ShoppingState.checked
        case .uncheckShoppingItem: return ShoppingState.pending
        case .haveShoppingItem: return ShoppingState.skipped
        default: return nil
        }
    }

    var isShoppingOp: Bool { shoppingRef != nil }

    /// Lista sobre la que actúa una op de lista, o lista de la tarea en una op de tarea; nil en las de la Compra.
    var listRef: Ref? {
        switch self {
        case .createTask(_, let listRef, _, _, _, _), .updateTask(_, let listRef, _, _, _, _),
             .completeTask(_, let listRef, _), .deleteTask(_, let listRef):
            return listRef
        case .createList(let local, _, _, _, _, _): return .local(local)
        case .updateList(let ref, _, _, _, _, _), .deleteList(let ref): return ref
        case .createShoppingItem, .checkShoppingItem, .uncheckShoppingItem, .haveShoppingItem: return nil
        }
    }

    var isTaskOp: Bool { taskRef != nil }

    /// Temporal que crea esta op (solo los creates).
    var createdLocal: Ref? {
        switch self {
        case .createTask(let local, _, _, _, _, _), .createList(let local, _, _, _, _, _),
             .createShoppingItem(let local, _, _, _, _, _, _): return .local(local)
        default: return nil
        }
    }

    var isCreate: Bool { createdLocal != nil }

    var isDelete: Bool {
        switch self {
        case .deleteTask, .deleteList: return true
        default: return false
        }
    }

    /// ¿Depende esta op del recurso `ref`? Una op de tarea depende de su tarea y de su lista; una de
    /// lista, de su lista; una de la Compra, de su artículo.
    func references(_ ref: Ref) -> Bool {
        if let taskRef, taskRef == ref { return true }
        if let shoppingRef, shoppingRef == ref { return true }
        return listRef == ref
    }

    /// Texto corto del recurso para los avisos («Leche», «la lista Compra»…).
    var subject: String? {
        switch self {
        case .createTask(_, _, let title, _, _, _), .updateTask(_, _, let title, _, _, _): return "«\(title)»"
        case .createList(_, let name, _, _, _, _), .updateList(_, let name, _, _, _, _): return "la lista «\(name)»"
        case .createShoppingItem(_, let label, _, _, _, _, _): return label.map { "«\($0)»" }
        case .completeTask, .deleteTask, .deleteList, .checkShoppingItem, .uncheckShoppingItem, .haveShoppingItem: return nil
        }
    }
}
