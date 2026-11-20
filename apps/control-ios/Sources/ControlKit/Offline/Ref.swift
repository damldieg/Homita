import Foundation

/// Referencia a una tarea o lista desde la cola offline (D-024): `.remote` es un ID del servidor y
/// `.local` un ID temporal (entero negativo) de un recurso creado sin conexión que aún no tiene ID
/// real. Al reproducir la cola, `.local` se traduce con el `idMap` del `OutboxStore`.
public enum Ref: Codable, Equatable, Hashable, Sendable {
    case remote(Int)
    case local(Int)

    /// Los IDs temporales son negativos; los del servidor, positivos.
    public init(id: Int) {
        self = id < 0 ? .local(id) : .remote(id)
    }

    /// El entero tal cual (negativo si es local).
    public var rawId: Int {
        switch self {
        case .remote(let id), .local(let id): return id
        }
    }

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    /// ID que se envía al servidor: el remoto, o el mapeo del temporal; `nil` si aún no se resolvió.
    public func resolved(with idMap: [Int: Int]) -> Int? {
        switch self {
        case .remote(let id): return id
        case .local(let id): return idMap[id]
        }
    }

    /// ID que ve la UI: el remoto si ya se conoce; si no, el temporal.
    public func displayId(with idMap: [Int: Int]) -> Int {
        resolved(with: idMap) ?? rawId
    }

    /// Misma referencia tras traducir el temporal (dos refs que apuntan al mismo recurso real).
    func normalized(with idMap: [Int: Int]) -> Ref {
        if case .local(let id) = self, let remote = idMap[id] { return .remote(remote) }
        return self
    }
}
