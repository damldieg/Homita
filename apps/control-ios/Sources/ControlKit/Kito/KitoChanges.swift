import Foundation

/// Canal de recarga de los cambios que hace Kito. Lo publica `KitoStore` tras guardar (en `ask` y en
/// `confirm`, también con un 409 parcial) y lo observan las pestañas. Es propio y no `DataFreshness`: aquel
/// recrea todas las pestañas y pierde su navegación; este solo avisa de qué tipos han cambiado.
@MainActor
@Observable
public final class KitoChanges: KitoChangePublishing {
    /// Veces que se ha publicado cada tipo (solo en memoria).
    public private(set) var counters: [KitoChangeKind: Int] = [:]

    public init() {}

    /// Suma uno a cada tipo afectado (una vez por publicación y tipo, aunque lleguen varios cambios del mismo).
    /// Los tipos desconocidos y la lista vacía no cambian nada.
    public func publish(_ changes: [KitoChange]) {
        let kinds = Set(changes.compactMap(\.kind))
        guard !kinds.isEmpty else { return }
        for kind in kinds { counters[kind, default: 0] += 1 }
    }

    /// Contador combinado de varios tipos: cambia si alguno de ellos se publica.
    public func counter(for kinds: Set<KitoChangeKind>) -> Int {
        kinds.reduce(0) { $0 + (counters[$1] ?? 0) }
    }
}

/// Qué tipos de cambio recarga cada almacén (mapeo de la decisión de diseño).
public enum KitoReloadTargets {
    /// Pestaña Tareas: listas y tareas.
    public static let tasks: Set<KitoChangeKind> = [.tarea, .lista]
    /// Agenda y eventos: eventos y calendarios (un calendario nuevo o borrado cambia la agenda).
    public static let agenda: Set<KitoChangeKind> = [.evento, .calendario]
    /// Lista de calendarios.
    public static let calendars: Set<KitoChangeKind> = [.calendario]
    /// Rutinas.
    public static let routines: Set<KitoChangeKind> = [.rutina]
    /// Pestaña Menú: menú semanal, recetas y compra.
    public static let meals: Set<KitoChangeKind> = [.menu, .receta, .compra]
    /// Inicio (eventos, tareas, rutinas y platos de hoy): todo salvo recetas y compra. Sus cargas también
    /// reprograman los avisos locales por `HomitaSync.refresh` (una vez por publicación).
    public static let inicio: Set<KitoChangeKind> = Set(KitoChangeKind.allCases).subtracting([.receta, .compra])
}

/// Último contador visto por un consumidor. `shouldReload` es verdadero una sola vez por cambio, lo vea
/// primero el `.onChange` (pestaña montada) o el `.onAppear` (pestaña que no estaba): nunca recarga dos veces.
public struct KitoReloadGate: Equatable {
    private var seen: Int

    public init(seen: Int) { self.seen = seen }

    public mutating func shouldReload(current: Int) -> Bool {
        guard current != seen else { return false }
        seen = current
        return true
    }
}
