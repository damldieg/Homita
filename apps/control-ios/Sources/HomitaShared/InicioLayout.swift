import Foundation

/// Bloques de Inicio que se pueden ordenar y ocultar (tarjeta [12]). El saludo y la cabecera siempre se ven.
public enum InicioBlock: String, Codable, CaseIterable, Sendable, Identifiable {
    case routines, meals, events, tasks

    public var id: String { rawValue }

    /// Nombre en Ajustes › Inicio y título de la tarjeta.
    public var title: String {
        switch self {
        case .routines: return "Rutinas de hoy"
        case .meals: return "Comidas de hoy"
        case .events: return "Hoy · Eventos"
        case .tasks: return "Tareas pendientes"
        }
    }
}

/// Orden y visibilidad de los bloques de Inicio. Se guarda en este iPhone, no en la cuenta.
public struct InicioLayout: Codable, Equatable, Sendable {
    /// Orden de los bloques; siempre contiene cada bloque una vez.
    public private(set) var order: [InicioBlock]
    public private(set) var hidden: Set<InicioBlock>

    /// Por defecto: el orden de siempre, todo visible.
    public init(order: [InicioBlock] = InicioBlock.allCases, hidden: Set<InicioBlock> = []) {
        self.order = Self.normalized(order)
        self.hidden = hidden
    }

    /// Bloques visibles en el orden elegido.
    public var visibleBlocks: [InicioBlock] { order.filter { !hidden.contains($0) } }

    public mutating func move(from source: IndexSet, to destination: Int) {
        var moved = order
        let items = source.sorted().map { moved[$0] }
        for index in source.sorted().reversed() { moved.remove(at: index) }
        let shift = source.filter { $0 < destination }.count
        moved.insert(contentsOf: items, at: destination - shift)
        order = moved
    }

    public mutating func setVisible(_ block: InicioBlock, _ visible: Bool) {
        if visible { hidden.remove(block) } else { hidden.insert(block) }
    }

    /// Al leer de disco se normaliza igual que al crear: un orden con repetidos o incompleto se corrige.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        self.order = Self.normalized(try raw.decode([InicioBlock].self, forKey: .order))
        self.hidden = try raw.decode(Set<InicioBlock>.self, forKey: .hidden)
    }

    private enum CodingKeys: String, CodingKey { case order, hidden }

    /// Quita duplicados y añade los bloques que falten al final, en el orden por defecto.
    /// Excepción: `.meals` se inserta justo tras `.routines` (migración del orden guardado antes de
    /// que existiera «Comidas de hoy»); si no hay `.routines`, va al final como los demás.
    static func normalized(_ order: [InicioBlock]) -> [InicioBlock] {
        var seen = Set<InicioBlock>()
        var result = order.filter { seen.insert($0).inserted }
        if !seen.contains(.meals), let routines = result.firstIndex(of: .routines) {
            result.insert(.meals, at: routines + 1)
            seen.insert(.meals)
        }
        result += InicioBlock.allCases.filter { !seen.contains($0) }
        return result
    }
}

/// Persistencia de `InicioLayout` en el grupo de la app (mismo patrón que las preferencias de avisos).
public struct InicioLayoutStore {
    public static let key = "inicio_layout_v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = HomitaShared.defaults) {
        self.defaults = defaults
    }

    /// Lo guardado, o el orden por defecto si no hay nada o no se puede leer.
    public func load() -> InicioLayout {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(InicioLayout.self, from: data) else {
            return InicioLayout()
        }
        return value
    }

    public func save(_ layout: InicioLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
