import Foundation

/// Configuración inyectada desde `Config.xcconfig` (generado por `scripts/gen-config.sh`) vía
/// Info.plist: `PlanifyBaseURL`, `SupabaseURL`, `SupabaseAnonKey`. Validación fail-fast: sin
/// placeholders, URL https (o http solo en loopback para `supabase functions serve`).
public struct AppConfig: Equatable {
    public static let planifyBaseURLKey = "PlanifyBaseURL"
    public static let supabaseURLKey = "SupabaseURL"
    public static let supabaseAnonKeyKey = "SupabaseAnonKey"

    public let planifyBaseURL: URL
    public let supabaseURL: URL
    public let supabaseAnonKey: String

    public enum ConfigError: Error, Equatable {
        /// Clave ausente o vacía.
        case missing(String)
        /// Quedó el placeholder de Config.xcconfig.example (`<ref>`, `<anon key>`, …).
        case placeholder(String)
        /// No es una URL válida.
        case invalidURL(String)
        /// `http://` solo se permite en loopback (debug local con `supabase functions serve`).
        case insecureURL(String)
    }

    public init(values: [String: String]) throws {
        let base = try Self.validateURL(values[Self.planifyBaseURLKey], key: Self.planifyBaseURLKey)
        let supabase = try Self.validateURL(values[Self.supabaseURLKey], key: Self.supabaseURLKey)
        let anonKey = try Self.validateKey(values[Self.supabaseAnonKeyKey], key: Self.supabaseAnonKeyKey)
        planifyBaseURL = base
        supabaseURL = supabase
        supabaseAnonKey = anonKey
    }

    public init(bundle: Bundle) throws {
        func raw(_ key: String) -> String? {
            bundle.object(forInfoDictionaryKey: key) as? String
        }
        try self.init(values: [
            Self.planifyBaseURLKey: raw(Self.planifyBaseURLKey) ?? "",
            Self.supabaseURLKey: raw(Self.supabaseURLKey) ?? "",
            Self.supabaseAnonKeyKey: raw(Self.supabaseAnonKeyKey) ?? ""
        ])
    }

    /// Arranque de la app: si falta la config, cae con un mensaje claro (el build ya falla antes
    /// con `scripts/check-config.sh`; esto cubre el caso de Info.plist sin inyectar).
    public static func load(bundle: Bundle = .main) -> AppConfig {
        do {
            return try AppConfig(bundle: bundle)
        } catch {
            fatalError("Configuración ausente o inválida (\(error)). Ejecuta apps/control-ios/scripts/gen-config.sh y compila con Config.xcconfig.")
        }
    }

    private static func validateKey(_ value: String?, key: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigError.missing(key)
        }
        guard !value.contains("<") else {
            throw ConfigError.placeholder(key)
        }
        return value
    }

    private static func validateURL(_ value: String?, key: String) throws -> URL {
        let raw = try validateKey(value, key: key)
        guard let url = URL(string: raw), let scheme = url.scheme, let host = url.host, !host.isEmpty else {
            throw ConfigError.invalidURL(key)
        }
        switch scheme {
        case "https":
            return url
        case "http":
            guard ["localhost", "127.0.0.1", "::1"].contains(host) else {
                throw ConfigError.insecureURL(key)
            }
            return url
        default:
            throw ConfigError.invalidURL(key)
        }
    }
}
