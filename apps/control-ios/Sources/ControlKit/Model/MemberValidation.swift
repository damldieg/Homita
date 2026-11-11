import Foundation

/// Validación de cliente de miembros del hogar (paridad con la Edge: nombre 1-50 codepoints,
/// color `#RRGGBB`). Puro y sin red.
public enum MemberValidation {
    public static let defaultColor = "#6923E2"
    public static let maxNameLength = 50

    /// Nombre recortado; el mismo texto que se envía.
    public static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isValidName(_ name: String) -> Bool {
        (1...maxNameLength).contains(trimmedName(name).codepointCount)
    }

    /// `#RRGGBB` sin distinguir mayúsculas.
    public static func isValidColor(_ color: String) -> Bool {
        color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    /// Mensaje en español o `nil` si es válido.
    public static func validate(name: String, color: String) -> String? {
        if trimmedName(name).isEmpty { return "El nombre es obligatorio" }
        if !isValidName(name) { return "El nombre admite como máximo 50 caracteres" }
        if !isValidColor(color) { return "El color debe ser #RRGGBB" }
        return nil
    }
}
