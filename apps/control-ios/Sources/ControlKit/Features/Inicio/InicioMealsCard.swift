import SwiftUI

/// Tarjeta «Comidas de hoy» de Inicio. Estado solo por la hora del hogar (la zona y la hora vienen
/// del servidor): finalizada, en curso, aviso (≤ 60 min) y más tarde. Se oculta sin menú aceptado.
struct InicioMealsCard: View {
    let store: InicioStore
    let dateText: String
    /// Abre la receta de la casilla tocada.
    let onOpenRecipe: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().overlay(Palette.line)
            if store.todayMeals.isEmpty {
                HomitaEmptyNote(text: "Hoy no hay comidas en el menú.")
            } else {
                VStack(spacing: Spacing.s2) {
                    ForEach(store.todayMeals) { meal in row(meal) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s5)
        .padding(.bottom, Spacing.s4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.line, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "fork.knife")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Comidas de hoy")
                    .font(HomitaFont.inter(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(dateText)
                    .font(HomitaFont.inter(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func row(_ meal: MealTodayItem) -> some View {
        let content = rowContent(meal)
        if let recipeId = meal.recipeId {
            Button { onOpenRecipe(recipeId) } label: { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private func rowContent(_ meal: MealTodayItem) -> some View {
        let phase = store.phase(of: meal)
        let isNow = phase == .now
        let isSoon = phase == .soon
        let tint: Color = isNow ? Palette.now : (isSoon ? Palette.soonText : (phase == .done ? Palette.inkMuted : Palette.accent))
        let background: Color = isNow ? Palette.nowBg : (isSoon ? Palette.soonBg : Palette.farBg)
        return HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: phase == .done ? "checkmark" : "fork.knife")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker(meal, phase))
                    .font(HomitaFont.inter(11, weight: .bold, relativeTo: .caption2))
                    .tracking(0.7)
                    .foregroundStyle(tint)
                Text(meal.title)
                    .font(HomitaFont.inter(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(phase == .done ? Palette.inkMuted : Palette.ink)
                    .strikethrough(phase == .done)
            }
            Spacer(minLength: Spacing.s2)
            Text(String(meal.time.prefix(5)))
                .font(HomitaFont.inter(15, weight: .bold, relativeTo: .body))
                .foregroundStyle(phase == .done ? Palette.inkMuted : Palette.ink)
        }
        .padding(Spacing.s3)
        .background(background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func kicker(_ meal: MealTodayItem, _ phase: InicioStore.MealPhase) -> String {
        let slot = MealSlotKind.title(meal.slot).uppercased()
        switch phase {
        case .now: return "\(slot) · EN CURSO"
        case .soon: return "\(slot) · EN \(store.minutesUntil(meal: meal) ?? 0) MIN"
        case .done, .later: return slot
        }
    }
}
