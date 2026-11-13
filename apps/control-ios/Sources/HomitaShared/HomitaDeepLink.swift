import Foundation

/// Destinos a los que llevan los widgets, la Live Activity y las notificaciones.
/// Se serializan como `homita://<destino>`.
public enum HomitaDeepLink: String, CaseIterable, Equatable, Sendable {
    case nuevaTarea = "nueva-tarea"
    case nuevoEvento = "nuevo-evento"
    case nuevaRutina = "nueva-rutina"
    case rutinas = "rutinas"
    case tareas = "tareas"
    case calendario = "calendario"
    case ajustesNotificaciones = "ajustes-notificaciones"

    public var url: URL {
        // El esquema y el destino son constantes ASCII: la URL siempre es válida.
        URL(string: "\(HomitaShared.urlScheme)://\(rawValue)")!
    }

    /// `nil` si la URL no es de Homita o el destino no existe.
    public init?(url: URL) {
        guard url.scheme == HomitaShared.urlScheme, let host = url.host, let link = Self(rawValue: host) else {
            return nil
        }
        self = link
    }

    public init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url: url)
    }
}
