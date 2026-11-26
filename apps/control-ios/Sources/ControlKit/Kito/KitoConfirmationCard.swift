import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Qué se muestra de una tarjeta de confirmación según su estado. Puro (sin vistas) para poder probarlo.
struct KitoConfirmationPresentation: Equatable {
    let texto: String
    let estado: KitoConfirmationState
    let detalle: String?

    init(_ confirmation: KitoConfirmation) {
        texto = confirmation.texto
        estado = confirmation.estado
        detalle = confirmation.detalle
    }

    /// Botones visibles: pendiente y enviando (en este último, desactivados y con progreso).
    var showsButtons: Bool { estado == .pendiente || estado == .enviando }
    var buttonsEnabled: Bool { estado == .pendiente }
    var confirmIsLoading: Bool { estado == .enviando }
    /// Resultado visible (sin botones).
    var resolvedLabel: String? { showsButtons ? nil : estado.label }

    /// Texto breve de la propuesta para las etiquetas de los botones.
    var shortText: String {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 60 ? String(t.prefix(60)) + "…" : t
    }

    var confirmAccessibilityLabel: String { "Confirmar: \(shortText)" }
    var cancelAccessibilityLabel: String { "Cancelar" }

    /// Etiqueta de VoiceOver de la tarjeta entera; el estado resuelto se lee al final.
    var accessibilityLabel: String {
        var out = "Kito pide confirmación: \(texto)"
        if estado == .enviando { out += ". Enviando" }
        if let label = resolvedLabel {
            out += ". \(label)"
            if let detalle, estado != .caducado { out += ". \(detalle)" }
        }
        return out
    }

    /// Anuncio al pasar a un estado resuelto (nil si no es resuelto).
    var announcement: String? {
        guard let label = resolvedLabel else { return nil }
        return label
    }
}

/// Tarjeta `confirmacion`: texto de la propuesta y, mientras está pendiente, «Confirmar» (rojo, token de error)
/// y «Cancelar». El estado vive en el store; la vista solo lo pinta y avisa de los toques.
struct KitoConfirmationCard: View {
    let confirmation: KitoConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onAppear: () -> Void

    private var model: KitoConfirmationPresentation { KitoConfirmationPresentation(confirmation) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(model.texto)
                .font(HomitaFont.inter(14))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            if model.showsButtons {
                HStack(spacing: Spacing.s2) {
                    HomitaButton(title: "Confirmar", kind: .destructiveOutline, isEnabled: model.buttonsEnabled, isLoading: model.confirmIsLoading, action: onConfirm)
                        .accessibilityLabel(model.confirmAccessibilityLabel)
                    HomitaButton(title: "Cancelar", kind: .secondary, isEnabled: model.buttonsEnabled, action: onCancel)
                        .accessibilityLabel(model.cancelAccessibilityLabel)
                }
            } else if let label = model.resolvedLabel {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(label)
                        .font(HomitaFont.inter(14, weight: .semibold))
                        .foregroundStyle(model.estado == .hecho || model.estado == .cancelado ? Palette.ink : Palette.err)
                    if let detalle = model.detalle, model.estado != .caducado {
                        Text(detalle)
                            .font(HomitaFont.inter(13))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.line, lineWidth: 1))
        // Con botones, el contenedor se agrupa sin esconderlos; resuelta, es un único elemento de lectura.
        .accessibilityElement(children: model.showsButtons ? .contain : .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .onAppear(perform: onAppear)
        .onChange(of: confirmation.estado) { _, _ in
            #if canImport(UIKit)
            if let text = model.announcement { UIAccessibility.post(notification: .announcement, argument: text) }
            #endif
        }
    }
}
