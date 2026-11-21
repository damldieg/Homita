import Foundation

/// Historial de Kito solo en el móvil: un fichero JSON por usuario y hogar en Application Support.
/// Sobrevive al cierre de la app y se borra al cerrar sesión (`clear(userId:)`). No se sube a Supabase.
public final class KitoHistoryStore {
    /// Mensajes guardados por conversación; los más antiguos se descartan al pasar de este tope.
    public static let maxStored = 200

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        if ReadCache.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Kito-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("ControlKit", isDirectory: true)
            .appendingPathComponent("Kito", isDirectory: true)
    }

    func fileURL(userId: Int, homeId: String) -> URL {
        directory
            .appendingPathComponent(String(userId), isDirectory: true)
            .appendingPathComponent("\(homeId).json")
    }

    /// Conversación del usuario en el hogar. Si no existe o no se puede leer, devuelve vacío.
    public func load(userId: Int, homeId: String) -> [KitoMessage] {
        guard let data = try? Data(contentsOf: fileURL(userId: userId, homeId: homeId)) else { return [] }
        return (try? JSONDecoder().decode([KitoMessage].self, from: data)) ?? []
    }

    /// Guarda la conversación (escritura atómica). Conserva solo los últimos `maxStored` mensajes.
    public func save(_ messages: [KitoMessage], userId: Int, homeId: String) throws {
        let url = fileURL(userId: userId, homeId: homeId)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let recortados = Array(messages.suffix(Self.maxStored))
        let data = try JSONEncoder().encode(recortados)
        try data.write(to: url, options: .atomic)
    }

    /// Borra todas las conversaciones del usuario (en todos sus hogares). Se llama al cerrar sesión.
    public func clear(userId: Int) {
        let dir = directory.appendingPathComponent(String(userId), isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
