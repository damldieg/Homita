import SwiftUI

extension View {
    /// Lista o formulario con la identidad Homita: fondo crema, filas en tarjeta y separadores
    /// de la paleta. Se aplica a cada `List`/`Form` de pantalla principal (B2).
    func homitaList() -> some View {
        self
            .font(HomitaFont.inter(17, relativeTo: .body))
            .foregroundStyle(Palette.ink)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .homitaNavigationBar()
    }

    /// Barra superior del mismo crema que el cuerpo (sin el blanco de sistema).
    func homitaNavigationBar() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Oculta la barra de navegación: la pestaña pinta su propia cabecera (`HomitaHeader`).
    func homitaHiddenNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
