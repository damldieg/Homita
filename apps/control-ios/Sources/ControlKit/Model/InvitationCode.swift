import Foundation

/// Código de invitación de un hogar (1.15): 32 caracteres hexadecimales (128 bits). Se comparte
/// copiándolo; aquí solo se normaliza y valida antes de enviarlo (el servidor repite ambas cosas
/// y responde el mismo 404 para cualquier código no válido).
public enum InvitationCode {
    /// Quita espacios y saltos de línea de los extremos y pasa a minúsculas.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `true` si el código normalizado tiene exactamente 32 caracteres `[0-9a-f]`.
    public static func isValid(_ raw: String) -> Bool {
        let code = normalize(raw)
        return code.count == 32 && code.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
