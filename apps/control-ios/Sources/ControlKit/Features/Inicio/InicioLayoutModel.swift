import Observation
import SwiftUI
import HomitaShared

/// Estado observable del orden y la visibilidad de Inicio (tarjeta [12]). Lo comparten Inicio y Ajustes.
@Observable
@MainActor
public final class InicioLayoutModel {
    public static let shared = InicioLayoutModel()

    public private(set) var layout: InicioLayout
    @ObservationIgnored private let store: InicioLayoutStore

    public init(store: InicioLayoutStore = InicioLayoutStore()) {
        self.store = store
        self.layout = store.load()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.move(from: source, to: destination)
        store.save(layout)
    }

    public func setVisible(_ block: InicioBlock, _ visible: Bool) {
        layout.setVisible(block, visible)
        store.save(layout)
    }
}
