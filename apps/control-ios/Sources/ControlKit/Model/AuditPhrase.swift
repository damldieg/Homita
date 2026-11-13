import Foundation

/// Frase en español de una entrada de auditoría (E4-10, decisión P-23: la genera el cliente a
/// partir de `action` y `payload`). Puro, sin UI. Si la acción no está en el mapa, usa una frase
/// genérica con el código técnico, para no ocultar nada.
public enum AuditPhrase {
    /// Etiquetas de los permisos más usados (códigos del catálogo de `home_permission`).
    static let permissionLabels: [String: String] = [
        "task.read": "Ver tareas",
        "task.edit": "Editar y ordenar tareas",
        "calendar.read": "Ver calendarios",
        "calendar.write": "Editar calendarios",
        "home.invite": "Invitar personas",
    ]

    /// Frase principal: «Ana activó «Editar y ordenar tareas» para Lucía».
    public static func sentence(action: String, actor: String?, payload: [String: String]) -> String {
        let who = actor?.isEmpty == false ? actor! : "Sistema"
        let permission = payload["permission"].map { permissionLabels[$0] ?? $0 }
        let member = payload["member_name"] ?? payload["person_name"]
        let forMember = member.map { " para \($0)" } ?? ""

        switch action {
        case "home.permission.grant":
            if let permission { return "\(who) activó «\(permission)»\(forMember)" }
        case "home.permission.revoke":
            if let permission { return "\(who) desactivó «\(permission)»\(forMember)" }
        case "home.invitation.create":
            let type = payload["type"] ?? payload["kind"]
            return type.map { "\(who) creó una invitación de tipo \($0)" } ?? "\(who) creó una invitación"
        case "home.invitation.revoke":
            return "\(who) revocó una invitación"
        case "membership.role_changed":
            if let role = payload["role"], let member { return "\(who) cambió el rol de \(member) a \(role)" }
        case "home.updated":
            return "\(who) actualizó el hogar"
        default:
            break
        }
        return "\(who) realizó «\(action)»"
    }
}
