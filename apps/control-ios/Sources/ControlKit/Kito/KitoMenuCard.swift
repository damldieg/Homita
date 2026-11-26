import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Qué se muestra de una tarjeta `menu`. Puro (sin vistas) para poder probarlo.
struct KitoMenuPresentation: Equatable {
    let menu: KitoMenu

    var title: String { "Menú de la semana del \(Self.dayLabel(menu.semana, withWeekday: false))" }

    /// El botón «Aceptar» se ve mientras no esté aceptado; se puede tocar salvo mientras se envía.
    var showsAccept: Bool { menu.resultado.canAccept || menu.resultado == .enviando }
    var acceptEnabled: Bool { menu.resultado.canAccept }
    var acceptIsLoading: Bool { menu.resultado == .enviando }
    var resultLabel: String? { menu.resultado == .pendiente ? nil : menu.resultado.label }

    /// Línea de un plato: «comida: Lentejas», con «(a cambiar: motivo)» si está marcado.
    static func line(_ dish: KitoMenuDish) -> String {
        let base = dish.franjaEs.isEmpty ? dish.titulo : "\(dish.franjaEs): \(dish.titulo)"
        guard dish.isRejected else { return base }
        if let motivo = dish.motivo { return "\(base) (a cambiar: \(motivo))" }
        return "\(base) (a cambiar)"
    }

    /// Texto completo para VoiceOver: semana, platos por día, los que se cambian y el resultado.
    var accessibilityLabel: String {
        var out = "Kito propone un menú. \(title)."
        for day in menu.days {
            out += " \(Self.dayLabel(day.dia, withWeekday: true)): " + day.dishes.map(Self.line).joined(separator: ", ") + "."
        }
        if !menu.rejected.isEmpty { out += " Platos a cambiar: \(menu.rejected.count)." }
        if let label = resultLabel { out += " \(label)." }
        return out
    }

    /// «lunes 23 de noviembre» (o «23 de noviembre»); si la fecha no se lee, el texto tal cual.
    static func dayLabel(_ iso: String, withWeekday: Bool) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = withWeekday ? "EEEE d 'de' MMMM" : "d 'de' MMMM"
        return f.string(from: date)
    }
}

/// Tarjeta `menu`: semana, platos por día (los marcados a cambiar, con su motivo) y «Aceptar». No acepta sola:
/// solo al tocar el botón, con la revisión de la tarjeta; si el menú cambió, lo dice y no acepta.
struct KitoMenuCard: View {
    let menu: KitoMenu
    let onAccept: () -> Void

    private var model: KitoMenuPresentation { KitoMenuPresentation(menu: menu) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(model.title)
                    .font(HomitaFont.inter(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                ForEach(menu.days, id: \.dia) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(KitoMenuPresentation.dayLabel(day.dia, withWeekday: true).capitalized(with: Locale(identifier: "es_ES")))
                            .font(HomitaFont.inter(12, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                        ForEach(Array(day.dishes.enumerated()), id: \.offset) { _, dish in
                            Text(KitoMenuPresentation.line(dish))
                                .font(HomitaFont.inter(13))
                                .foregroundStyle(dish.isRejected ? Palette.err : Palette.ink)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilityLabel)
            if model.showsAccept {
                HomitaButton(title: "Aceptar", kind: .primary, isEnabled: model.acceptEnabled, isLoading: model.acceptIsLoading, action: onAccept)
                    .accessibilityLabel("Aceptar el menú de la semana del \(KitoMenuPresentation.dayLabel(menu.semana, withWeekday: false))")
            }
            if let label = model.resultLabel {
                Text(label)
                    .font(HomitaFont.inter(14, weight: .semibold))
                    .foregroundStyle(menu.resultado == .aceptado ? Palette.ink : Palette.err)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.line, lineWidth: 1))
        .onChange(of: menu.resultado) { _, _ in
            #if canImport(UIKit)
            if let text = model.resultLabel { UIAccessibility.post(notification: .announcement, argument: text) }
            #endif
        }
    }
}
