import Foundation

/// Fila de `GET home`: hogar del usuario con su rol (`docs/CONTRATOS_HOME.md`, `[HOME_ITEM]`).
public struct HomeItem: Codable, Equatable, Sendable {
    public let homeId: Int
    public let name: String
    public let role: String
    public let isDefault: Bool
    public let isPersonal: Bool

    public init(homeId: Int, name: String, role: String, isDefault: Bool, isPersonal: Bool) {
        self.homeId = homeId
        self.name = name
        self.role = role
        self.isDefault = isDefault
        self.isPersonal = isPersonal
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case role
        case isDefault = "is_default"
        case isPersonal = "is_personal"
    }
}

/// `HOME_DETAIL` (respuesta de `POST home/create`): solo se decodifican `id` y `name`; el resto
/// de campos del contrato se ignora.
public struct HomeDetail: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// Respuesta de `PATCH home/default`.
public struct DefaultHomeResponse: Codable, Equatable, Sendable {
    public let defaultHomeId: Int

    public init(defaultHomeId: Int) {
        self.defaultHomeId = defaultHomeId
    }

    enum CodingKeys: String, CodingKey {
        case defaultHomeId = "default_home_id"
    }
}

/// Body de `POST home/create`. Sin `timezone`: el servidor aplica su valor por defecto.
public struct CreateHomeBody: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Body de `PATCH home/default`.
public struct SetDefaultHomeBody: Codable, Equatable, Sendable {
    public let homeId: Int

    public init(homeId: Int) {
        self.homeId = homeId
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
    }
}
