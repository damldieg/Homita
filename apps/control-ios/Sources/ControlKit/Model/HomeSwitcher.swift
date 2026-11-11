import Foundation

/// Fila del selector "Mis hogares" (Perfil, 1.15c).
public struct HomeSwitcherRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let roleLabel: String
    public let isActive: Bool
}

/// Lógica pura del selector de hogares: una fila por hogar de `GET home`, con rol y marca de activo.
public enum HomeSwitcher {
    public static func roleLabel(_ role: String) -> String {
        role == "admin" ? "Administrador" : "Miembro"
    }

    public static func rows(homes: [HomeItem], activeHomeId: String?) -> [HomeSwitcherRow] {
        homes.map {
            HomeSwitcherRow(id: $0.homeId, name: $0.name, roleLabel: roleLabel($0.role),
                            isActive: String($0.homeId) == activeHomeId)
        }
    }
}
