import Foundation
import Observation

/// Estado de los datos que ve la app (E0-06): sin conexión y, cuando se muestra caché, la fecha
/// de la última lectura correcta. Lo lee el banner de sin conexión.
@MainActor
@Observable
public final class DataFreshness {
    public static let shared = DataFreshness()

    /// Sin red según `NWPathMonitor`.
    public private(set) var isOffline = false
    /// Fecha de la lectura que se muestra desde caché; `nil` = datos en vivo.
    public private(set) var staleSince: Date?
    /// Incrementa al pulsar «Reintentar»: la navegación recrea las pestañas y recarga sus datos.
    public private(set) var reloadToken = 0

    public init() {}

    public func markStale(since date: Date) {
        staleSince = date
    }

    public func markFresh() {
        staleSince = nil
    }

    public func setOffline(_ offline: Bool) {
        isOffline = offline
    }

    public func requestReload() {
        reloadToken += 1
    }
}
