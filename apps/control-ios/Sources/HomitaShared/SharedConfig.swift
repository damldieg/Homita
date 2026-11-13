import Foundation

/// Constantes y almacenamiento compartidos entre la app (`ControlKit`) y la extensión de widgets
/// (`HomitaWidgets`). Este módulo no tiene dependencias: lo enlazan los dos.
public enum HomitaShared {
    /// App Group del equipo (firma gratuita incluida). Debe coincidir con los `.entitlements` de la
    /// app y de la extensión (`apps/control-ios/Entitlements`).
    public static let appGroupId = "group.com.lito.planify.control.ios"

    /// Esquema de los enlaces profundos (`homita://nueva-tarea`).
    public static let urlScheme = "homita"

    /// Identificadores de los widgets (`kind`), para recargar solo los nuestros.
    public static let routinesWidgetKind = "com.lito.planify.control.ios.widget.routines"
    public static let quickActionsWidgetKind = "com.lito.planify.control.ios.widget.quick"

    /// Ventana «en curso» de una rutina y antelación del aviso (misma regla que `RoutineStatus`).
    public static let routineWindow: TimeInterval = 3600
    public static let routineSoonWindow: TimeInterval = 3600

    /// Carpeta del App Group; `nil` si la firma no incluye el grupo (el widget no puede leer datos).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    /// ¿Se puede compartir datos con la extensión?
    public static var isSharingAvailable: Bool { containerURL != nil }

    /// `UserDefaults` del grupo; sin grupo cae a los de la app (la extensión no los verá).
    public static var defaults: UserDefaults {
        guard isSharingAvailable, let shared = UserDefaults(suiteName: appGroupId) else { return .standard }
        return shared
    }
}
