import Foundation
import Security

/// Almacenamiento de secretos de sesión. Implementación real: Keychain (`kSecClassGenericPassword`,
/// accesible tras el primer desbloqueo). NUNCA UserDefaults: los tokens no tocan plist.
public protocol TokenStore: AnyObject {
    func set(_ value: String, forKey key: String) throws
    func get(_ key: String) throws -> String?
    func remove(_ key: String) throws
}

public enum TokenStoreError: Error, Equatable {
    case status(Int32)
    case encoding
}

/// Wrapper de Keychain (genérico, service fijo por app). Tests unitarios sobre `InMemoryTokenStore`;
/// la prueba save→load→delete real se ejecuta en simulador con el proyecto Xcode (ver README).
public final class KeychainTokenStore: TokenStore {
    public let service: String

    public init(service: String = "com.lito.planify.control.ios") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    public func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { throw TokenStoreError.encoding }
        var query = baseQuery(key)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let result = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
            guard result == errSecSuccess else { throw TokenStoreError.status(result) }
        } else {
            guard status == errSecSuccess else { throw TokenStoreError.status(status) }
        }
    }

    public func get(_ key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TokenStoreError.status(status) }
        guard let value = String(data: data, encoding: .utf8) else { throw TokenStoreError.encoding }
        return value
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenStoreError.status(status) }
    }
}

/// Store en memoria para tests (mismos semánticos que Keychain: sobreescritura y borrado).
public final class InMemoryTokenStore: TokenStore {
    private var storage: [String: String] = [:]

    public init() {}

    public func set(_ value: String, forKey key: String) throws {
        storage[key] = value
    }

    public func get(_ key: String) throws -> String? {
        storage[key]
    }

    public func remove(_ key: String) throws {
        storage[key] = nil
    }
}
