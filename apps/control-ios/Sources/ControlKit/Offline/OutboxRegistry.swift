import Foundation

/// Reparte una sola `OutboxStore` por par usuario + hogar, para que la UI y `BackgroundRefresh`
/// compartan el mismo objeto (D-024). El directorio es inyectable para los tests (R15).
@MainActor
public final class OutboxRegistry {
    /// Registro de la app (`Application Support/ControlKit/Outbox`; bajo XCTest, un directorio temporal).
    public static let shared = OutboxRegistry(directory: defaultDirectory())

    public let directory: URL
    private var stores: [Key: OutboxStore] = [:]

    private struct Key: Hashable {
        let userId: Int
        let homeId: String
    }

    public init(directory: URL) {
        self.directory = directory
    }

    nonisolated static func defaultDirectory() -> URL {
        if ReadCache.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Outbox-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("ControlKit", isDirectory: true)
            .appendingPathComponent("Outbox", isDirectory: true)
    }

    /// Cola del usuario en el hogar (se carga de disco la primera vez).
    public func store(user userId: Int, home homeId: String) -> OutboxStore {
        let key = Key(userId: userId, homeId: homeId)
        if let existing = stores[key] { return existing }
        let store = OutboxStore(userId: userId, homeId: homeId, directory: directory)
        stores[key] = store
        return store
    }

    /// Cambios pendientes del usuario en todos sus hogares (los que están en disco también), para
    /// avisar antes de cerrar sesión (T29).
    public func pendingCount(userId: Int) -> Int {
        let userDirectory = directory.appendingPathComponent(String(userId), isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: nil)) ?? []
        var homes = Set(files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
        for key in stores.keys where key.userId == userId { homes.insert(key.homeId) }
        return homes.reduce(0) { $0 + store(user: userId, home: $1).pendingCount }
    }

    /// Borra todas las colas (cierre de sesión manual).
    public func removeAll() {
        for store in stores.values { store.wipe() }
        stores = [:]
        try? FileManager.default.removeItem(at: directory)
    }

    /// Borra las colas de cualquier otro usuario (al entrar con una cuenta distinta).
    public func retainOnly(userId: Int) {
        for (key, store) in stores where key.userId != userId {
            store.wipe()
            stores[key] = nil
        }
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent != String(userId) {
            try? manager.removeItem(at: entry)
        }
    }
}
