import Foundation

/// Código de vinculación de una pantalla (dashboard-vinculacion-qr): los 6 dígitos que muestra el marco, en texto o en QR.
/// Un QR que no sea exactamente esos 6 dígitos (con espacios o guiones alrededor) se rechaza.
public enum PairingCode {
    public static func parse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return trimmed
    }
}
