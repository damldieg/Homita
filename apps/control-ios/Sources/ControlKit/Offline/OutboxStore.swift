import Foundation
import Observation

/// Aviso de una op descartada al reproducir la cola (4xx o «no existe») o confirmada sin alguna
/// persona asignada (0038): lo muestra un toast.
public struct OutboxNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String

    public init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
}

/// Cola offline de un usuario en un hogar (D-024): ops en orden FIFO, mapeo de IDs temporales a
/// reales y contador de IDs temporales. Se guarda en disco tras cada cambio (escritura atómica,
/// protección `completeUntilFirstUserAuthentication` para el replay en segundo plano con el equipo
/// bloqueado, fuera de la copia de seguridad). Vive fuera de `ReadCache`: limpiar la caché no la toca.
@MainActor
@Observable
public final class OutboxStore {
    /// Tope de entradas de `idMap` (las más antiguas se olvidan primero si ninguna op las usa).
    public static let idMapLimit = 500
    /// Opciones de escritura del archivo de la cola (R11).
    public static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    /// Protección del archivo de la cola (R11); en macOS (tests) el sistema no la aplica igual.
    public static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication

    public let userId: Int
    public let homeId: String
    public private(set) var ops: [PendingOp] = []
    /// Temporal → ID real de los creates ya confirmados. Se conserva hasta `signOut` o cambio de usuario.
    public private(set) var idMap: [Int: Int] = [:]
    /// Próximo ID temporal (decreciente desde -1).
    public private(set) var nextLocalId = -1
    /// Sube con cada ack: las vistas recargan y los `load*` en vuelo descartan su resultado.
    public private(set) var generation = 0
    /// Avisos (descartes y asignaciones quitadas) pendientes de mostrar.
    public private(set) var notices: [OutboxNotice] = []
    /// Op que el replayer está enviando (inmutable para la compactación).
    public private(set) var inFlightId: UUID?

    @ObservationIgnored public let fileURL: URL
    /// Pasada del replayer en curso sobre esta cola. Vive aquí y no en `OutboxReplayer` para que el
    /// vuelo único valga entre replayers distintos sobre la misma store (R1-02).
    @ObservationIgnored var replayTask: Task<ReplaySummary, Never>?

    /// Forma persistida.
    struct Snapshot: Codable {
        var ops: [PendingOp]
        var idMap: [Int: Int]
        var nextLocalId: Int
    }

    public init(userId: Int, homeId: String, directory: URL) {
        self.userId = userId
        self.homeId = homeId
        self.fileURL = Self.fileURL(directory: directory, userId: userId, homeId: homeId)
        load()
    }

    /// `<directorio>/<userId>/<homeId>.json`.
    static func fileURL(directory: URL, userId: Int, homeId: String) -> URL {
        let safeHome = homeId.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" } ? homeId : "home"
        return directory
            .appendingPathComponent(String(userId), isDirectory: true)
            .appendingPathComponent(safeHome)
            .appendingPathExtension("json")
    }

    public var isEmpty: Bool { ops.isEmpty }
    public var pendingCount: Int { ops.count }

    // MARK: - IDs

    /// Reserva un ID temporal nuevo (negativo).
    public func makeLocalId() -> Int {
        let id = nextLocalId
        nextLocalId -= 1
        persist()
        return id
    }

    /// ID real de un temporal ya confirmado; el mismo ID si es remoto o aún no se resolvió.
    public func resolve(_ id: Int) -> Int {
        id < 0 ? (idMap[id] ?? id) : id
    }

    /// Referencia para un ID de la UI: remota si es real o el temporal ya se resolvió.
    public func ref(for id: Int) -> Ref {
        Ref(id: resolve(id))
    }

    // MARK: - Cola

    /// Encola con compactación (la op en vuelo no se toca).
    public func enqueue(_ op: PendingOp) {
        ops = OutboxCompactor.enqueue(op, into: ops, inFlight: inFlightId, idMap: idMap)
        persist()
    }

    /// Op confirmada por el servidor: guarda el mapeo si era un create, la quita y sube `generation`.
    /// `notice` deja un aviso para el toast (0038: se confirmó sin alguna persona asignada).
    public func ack(_ opId: UUID, remoteId: Int? = nil, notice: String? = nil) {
        if let remoteId, let op = ops.first(where: { $0.id == opId }), case .local(let local)? = op.kind.createdLocal {
            idMap[local] = remoteId
            trimIdMap()
        }
        ops.removeAll { $0.id == opId }
        if inFlightId == opId { inFlightId = nil }
        generation += 1
        if let notice { notices.append(OutboxNotice(message: notice)) }
        persist()
    }

    /// Reescribe el contenido de una op y lo guarda en disco antes de reenviarla (0038: el replay
    /// quita personas sin acceso). Solo vale para la op en vuelo o la primera de la cola, que la
    /// compactación ya no toca; en otra op no hace nada. El llamador conserva el mismo recurso
    /// (temporal y lista): solo cambian los datos que viajan.
    public func replaceKind(_ opId: UUID, with kind: PendingOp.Kind) {
        guard let index = ops.firstIndex(where: { $0.id == opId }),
              opId == inFlightId || index == 0 else { return }
        ops[index].kind = kind
        persist()
    }

    /// Descarta la op y las que dependen de ella (`dependents`), con aviso opcional.
    public func discard(_ opId: UUID, dependents: [Ref] = [], notice: String? = nil) {
        let map = idMap
        var refs = Set(dependents.map { $0.normalized(with: map) })
        var removed: Set<UUID> = []
        if let op = ops.first(where: { $0.id == opId }) {
            removed.insert(opId)
            if let created = op.kind.createdLocal { refs.insert(created) }
        }
        let depends: (PendingOp) -> Bool = { op in
            refs.contains { ref in
                op.kind.taskRef?.normalized(with: map) == ref || op.kind.listRef.normalized(with: map) == ref
            }
        }
        // Cierre transitivo: un create descartado arrastra las ops de su temporal, y así sucesivamente.
        var changed = !refs.isEmpty
        while changed {
            changed = false
            for op in ops where !removed.contains(op.id) && op.id != inFlightId && depends(op) {
                removed.insert(op.id)
                changed = true
                if let created = op.kind.createdLocal { refs.insert(created) }
            }
        }
        ops.removeAll { removed.contains($0.id) }
        if let inFlightId, removed.contains(inFlightId) { self.inFlightId = nil }
        if let notice { notices.append(OutboxNotice(message: notice)) }
        persist()
    }

    /// Suma un intento fallido (red o 5xx) a la op.
    public func recordAttempt(_ opId: UUID) {
        guard let index = ops.firstIndex(where: { $0.id == opId }) else { return }
        ops[index].attempts += 1
        persist()
    }

    func beginFlight(_ opId: UUID) {
        inFlightId = opId
    }

    func endFlight() {
        inFlightId = nil
    }

    public func dismissNotice(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    /// Vacía la cola en memoria y borra su archivo (`signOut` o cambio de usuario).
    func wipe() {
        ops = []
        idMap = [:]
        notices = []
        inFlightId = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        ops = snapshot.ops
        idMap = snapshot.idMap
        nextLocalId = min(snapshot.nextLocalId, -1)
    }

    private func persist() {
        let snapshot = Snapshot(ops: ops, idMap: idMap, nextLocalId: nextLocalId)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: fileURL, options: Self.writingOptions)) != nil else { return }
        #if os(iOS)
        try? manager.setAttributes([.protectionKey: Self.fileProtection], ofItemAtPath: fileURL.path)
        #endif
        Self.excludeFromBackup(directory)
        Self.excludeFromBackup(fileURL)
    }

    private static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// Olvida los mapeos más antiguos (temporales más cercanos a -1) que ninguna op usa.
    private func trimIdMap() {
        guard idMap.count > Self.idMapLimit else { return }
        let inUse = Set(ops.flatMap { op -> [Int] in
            [op.kind.taskRef, op.kind.listRef].compactMap { ref in
                if case .local(let id)? = ref { return id }
                return nil
            }
        })
        for local in idMap.keys.sorted(by: >) where idMap.count > Self.idMapLimit && !inUse.contains(local) {
            idMap[local] = nil
        }
    }
}
