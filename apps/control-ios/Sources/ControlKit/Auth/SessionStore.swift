import Foundation

/// Sesión iniciada (sin secretos).
public struct UserSession: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let email: String

    public init(id: Int, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

/// Estado de sesión único de la app: access token + refresh token en `TokenStore` (Keychain),
/// perfil en memoria. El acceso a red pasa por `accessToken`; `signOut()` borra todo (no hay
/// endpoint de revocación conocido).
@Observable
public final class SessionStore {
    public private(set) var session: UserSession?
    public private(set) var accessToken: String?
    public private(set) var refreshToken: String?

    private let store: TokenStore

    private enum Key {
        static let access = "access_token"
        static let refresh = "refresh_token"
        static let userId = "user_id"
        static let userName = "user_name"
        static let userEmail = "user_email"
    }

    public init(store: TokenStore) {
        self.store = store
    }

    /// Recupera la sesión persistida (arranque). Tolerante a Keychain reseteado (firma gratuita):
    /// si falta el token, no hay sesión y se vuelve a login.
    public func restore() {
        accessToken = try? store.get(Key.access) ?? nil
        refreshToken = try? store.get(Key.refresh) ?? nil
        guard let idString = try? store.get(Key.userId) ?? nil,
              let id = Int(idString),
              let name = try? store.get(Key.userName) ?? nil,
              let email = try? store.get(Key.userEmail) ?? nil,
              accessToken != nil else {
            return
        }
        session = UserSession(id: id, name: name, email: email)
    }

    /// Login/registro: guarda tokens y perfil.
    public func saveSession(user: UserResponse, accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        session = UserSession(id: user.id, name: user.name, email: user.email)
        try? store.set(accessToken, forKey: Key.access)
        if let refreshToken {
            try? store.set(refreshToken, forKey: Key.refresh)
        }
        try? store.set(String(user.id), forKey: Key.userId)
        try? store.set(user.name, forKey: Key.userName)
        try? store.set(user.email, forKey: Key.userEmail)
    }

    /// Refresco GoTrue: rota ambos tokens.
    public func updateTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        try? store.set(access, forKey: Key.access)
        try? store.set(refresh, forKey: Key.refresh)
    }

    /// `PATCH user/update` (la respuesta no trae token: se conserva el actual).
    public func updateProfile(name: String, email: String) {
        guard let current = session else { return }
        session = UserSession(id: current.id, name: name, email: email)
        try? store.set(name, forKey: Key.userName)
        try? store.set(email, forKey: Key.userEmail)
    }

    /// Logout local: borra Keychain y estado en memoria.
    public func signOut() {
        session = nil
        accessToken = nil
        refreshToken = nil
        for key in [Key.access, Key.refresh, Key.userId, Key.userName, Key.userEmail] {
            try? store.remove(key)
        }
    }
}
