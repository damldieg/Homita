import Foundation
import HomitaShared

/// Enlace profundo pendiente (de un widget, la Live Activity o una notificación). Lo consume la
/// pantalla de destino: `MainTabView` cambia de pestaña, Inicio abre «+ Tarea»/«+ Evento» y
/// Ajustes abre Notificaciones.
@Observable
public final class DeepLinkCenter {
    public static let shared = DeepLinkCenter()

    public private(set) var pending: HomitaDeepLink?

    public init() {}

    public func open(_ link: HomitaDeepLink) {
        pending = link
    }

    /// Abre una URL `homita://…`; ignora cualquier otra.
    @discardableResult
    public func open(url: URL) -> Bool {
        guard let link = HomitaDeepLink(url: url) else { return false }
        pending = link
        return true
    }

    /// Marca el enlace como atendido si sigue siendo `link`.
    public func consume(_ link: HomitaDeepLink) {
        if pending == link { pending = nil }
    }
}
