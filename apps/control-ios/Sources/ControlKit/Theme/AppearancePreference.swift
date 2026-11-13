import SwiftUI

/// Preferencia de apariencia del usuario (Ajustes): seguir al sistema, claro u oscuro.
/// Se guarda en `UserDefaults` (es una preferencia del dispositivo, no datos del hogar).
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system, light, dark

    public static let storageKey = "homita.appearance"

    /// Esquema forzado para `preferredColorScheme`; `nil` = sigue al sistema.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// ¿Se ve en oscuro? `systemDark` es el modo actual del sistema.
    public func resolvedIsDark(systemDark: Bool) -> Bool {
        switch self {
        case .system: return systemDark
        case .light: return false
        case .dark: return true
        }
    }
}
