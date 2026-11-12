import SwiftUI

/// Campo de formulario con error en línea bajo el campo (E0-10). Sustituye a la alerta «Aviso/OK»
/// para errores de validación. El texto escrito no se toca.
struct HomitaFormField: View {
    let placeholder: String
    @Binding var text: String
    /// Mensaje de error; `nil` = sin error.
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HomitaField(placeholder: placeholder, text: $text)
            if let error {
                HomitaErrorText(text: error)
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .animation(.easeOut(duration: 0.15), value: error)
    }
}
