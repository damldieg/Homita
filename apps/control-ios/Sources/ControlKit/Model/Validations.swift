import Foundation

/// Validación de cliente del evento (paridad con la Edge): `POST event/create` exige `title` +
/// `date_at` — devuelve el mensaje en español para la UI, o `nil` si es válido.
public enum EventValidation {
    public static func validate(title: String, dateAt: String, endDate: String? = nil) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "El título es obligatorio"
        }
        if dateAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "La fecha es obligatoria"
        }
        // RN-2: el fin (solo día, comparable como texto 'YYYY-MM-DD') no puede ser anterior al día de inicio.
        if let endDate, !endDate.isEmpty, endDate < String(dateAt.prefix(10)) {
            return "La fecha de fin no puede ser anterior al inicio"
        }
        return nil
    }
}

/// Validación en línea del título de una tarea (E0-10). Vacío = error; el resto lo decide el servidor.
public enum TaskTitleValidation {
    public static func message(for title: String) -> String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "El título es obligatorio" : nil
    }
}

/// Acciones disponibles sobre una persona. Las compartidas (`editable=false`) son solo lectura.
public enum PersonAction: Equatable, Sendable {
    case edit
    case delete
}

public enum PersonActions {
    public static func available(editable: Bool) -> [PersonAction] {
        editable ? [.edit, .delete] : []
    }
}

extension String {
    /// Longitud en codepoints UTF-8 (equivalente a `mb_strlen` de PHP; no unidades UTF-16).
    public var codepointCount: Int {
        unicodeScalars.count
    }
}
