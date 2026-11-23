import SwiftUI
import HomitaShared

/// Ajustes › Inicio: reordenar los bloques arrastrando y mostrar u ocultar cada uno (tarjeta [12]).
struct InicioSettingsView: View {
    @State private var model = InicioLayoutModel.shared

    var body: some View {
        List {
            Section {
                ForEach(model.layout.order) { block in
                    Toggle(block.title, isOn: Binding(
                        get: { !model.layout.hidden.contains(block) },
                        set: { model.setVisible(block, $0) }
                    ))
                    .accessibilityIdentifier("inicio.ajustes.\(block.rawValue)")
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Arrastra para cambiar el orden. Se guarda en este iPhone.")
            }
        }
        #if os(iOS)
        // Las asas de reordenar siempre visibles: así el interruptor y el arrastre funcionan a la vez.
        .environment(\.editMode, .constant(.active))
        #endif
        .navigationTitle("Inicio")
        .background(Palette.background.ignoresSafeArea())
    }
}
