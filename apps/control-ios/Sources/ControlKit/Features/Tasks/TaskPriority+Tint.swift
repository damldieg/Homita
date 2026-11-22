import Foundation

extension TaskPriority {
    /// Color de la prioridad, compartido por la etiqueta de prioridad de Tareas e Inicio.
    var tintHex: String {
        switch self {
        case .alta: return Palette.accentHex
        case .media: return Palette.soonHex
        case .baja: return Palette.sageHex
        }
    }
}
