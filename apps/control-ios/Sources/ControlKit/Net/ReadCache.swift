import Foundation
import CryptoKit

/// Caché de lectura en disco (E0-06): cuerpo de cada GET correcto y la fecha en que se leyó.
/// Clave = método + ruta + query + hogar activo, así no se mezclan datos de dos hogares.
/// No se guardan rutas de invitaciones ni de usuario (códigos y credenciales).
public final class ReadCache: @unchecked Sendable {
    /// Caché de la app (carpeta Caches del sistema, bajo «ReadCache»). Bajo XCTest está desactivada:
    /// los tests que prueban la caché crean la suya.
    public static let shared = ReadCache(directory: defaultDirectory(), enabled: !isRunningTests)

    public struct Entry: Codable, Equatable, Sendable {
        public let savedAt: Date
        public let body: Data
    }

    private let directory: URL
    private let enabled: Bool
    private let lock = NSLock()

    public init(directory: URL, enabled: Bool = true) {
        self.directory = directory
        self.enabled = enabled
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    static func defaultDirectory() -> URL {
        if isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("ReadCache-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("ReadCache", isDirectory: true)
    }

    /// ¿Se puede cachear esta petición? Solo GET autenticados de datos del hogar.
    public static func isCacheable(_ request: APIRequest) -> Bool {
        guard request.method == .get, !request.isPublic else { return false }
        return !(request.path.contains("invitation") || request.path.hasPrefix("user"))
    }

    /// Clave estable (SHA-256) para la petición y el hogar activo.
    public static func key(for request: APIRequest, homeId: String?) -> String {
        let query = request.query
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        let raw = "\(request.method) \(request.path)?\(query) home=\(homeId ?? "-")"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func save(key: String, body: Data, at date: Date = Date()) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(Entry(savedAt: date, body: body)) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    public func load(key: String) -> Entry? {
        guard enabled else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    /// Borra toda la caché (cierre de sesión y cambio de hogar).
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("json")
    }
}
