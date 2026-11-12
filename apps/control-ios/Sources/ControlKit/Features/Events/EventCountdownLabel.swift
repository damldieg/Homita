import SwiftUI

/// Etiqueta discreta de cuenta atrás ("en 25 min") bajo el título de un evento; no pinta nada
/// si el evento ya empezó o falta más de 2 h. Compartida por Inicio y la vista Día.
struct EventCountdownLabel: View {
    let dateAt: String

    var body: some View {
        if let text = EventCountdown.label(dateAt: dateAt) {
            Text(text)
                .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(Palette.accent)
        }
    }
}
