import Foundation

/// Texto de la confirmación de borrado (E0-07, D-7): «¿Eliminar «X»?» más una línea de consecuencia.
/// Con varios elementos (swipe sobre una selección) usa el recuento en lugar del nombre.
enum DeleteConfirmation {
    static func message(names: [String], consequence: String) -> String {
        switch names.count {
        case 0: return "¿Eliminar?\n\(consequence)"
        case 1: return "¿Eliminar «\(names[0])»?\n\(consequence)"
        default: return "¿Eliminar \(names.count) elementos?\n\(consequence)"
        }
    }
}
