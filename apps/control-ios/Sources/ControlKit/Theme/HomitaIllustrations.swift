import SwiftUI

/// Casos con ilustración propia en los estados vacíos de Homita.
enum HomitaIllustrationKind {
    case tasks, lists, events, routines, calendars
}

/// Ilustraciones vectoriales de Homita (formas SwiftUI, paleta del dashboard). Se usan solo dentro de
/// `HomitaEmptyState`, que es el componente común de los estados vacíos.
struct HomitaIllustration: View {
    let kind: HomitaIllustrationKind

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.accent.opacity(0.10))
                .frame(width: 150, height: 150)
            switch kind {
            case .tasks: tasks
            case .lists: lists
            case .events: events
            case .routines: routines
            case .calendars: calendars
            }
        }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }

    /// Tarjeta de tareas: dos pendientes y una completada.
    private var tasks: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.cardBorder, lineWidth: 1))
            .frame(width: 92, height: 108)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    taskRow(done: true)
                    taskRow(done: false)
                    taskRow(done: false)
                }
                .padding(.top, 18)
                .padding(.horizontal, 14)
            }
            .rotationEffect(.degrees(-4))
    }

    private func taskRow(done: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(done ? Palette.online : Color.clear)
                .overlay(Circle().stroke(done ? Palette.online : Palette.inkMuted, lineWidth: 2))
                .frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 3)
                .fill(done ? Palette.inkMuted.opacity(0.5) : Palette.line)
                .frame(width: 44, height: 6)
        }
    }

    /// Tres listas apiladas, cada una con su color.
    private var lists: some View {
        ZStack {
            listCard(color: Palette.warm).rotationEffect(.degrees(-8)).offset(x: -6, y: 6)
            listCard(color: Palette.online).rotationEffect(.degrees(5)).offset(x: 8, y: 2)
            listCard(color: Palette.accent)
        }
    }

    private func listCard(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.cardBorder, lineWidth: 1))
            .frame(width: 96, height: 60)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    RoundedRectangle(cornerRadius: 3).fill(Palette.line).frame(width: 48, height: 6)
                }
                .padding(.leading, 12)
            }
    }

    /// Hoja de calendario con cabecera de color y un día marcado.
    private var events: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.cardBorder, lineWidth: 1))
            .frame(width: 100, height: 100)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.accent).frame(height: 24)
                    VStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { col in
                                    Circle()
                                        .fill(row == 1 && col == 2 ? Palette.accent : Palette.line)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
    }

    /// Flecha circular: una repetición que vuelve sobre sí misma.
    private var routines: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 92, height: 92)
            Circle()
                .trim(from: 0.58, to: 0.72)
                .stroke(Palette.warm, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 92, height: 92)
            Circle()
                .fill(Palette.card)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Palette.accent, lineWidth: 3))
        }
    }

    /// Tres calendarios superpuestos, uno por color.
    private var calendars: some View {
        ZStack {
            calendarChip(color: Palette.online).offset(x: -18, y: 14).rotationEffect(.degrees(-6))
            calendarChip(color: Palette.warm).offset(x: 18, y: 10).rotationEffect(.degrees(6))
            calendarChip(color: Palette.accent)
        }
    }

    private func calendarChip(color: Color) -> some View {
        VStack(spacing: 0) {
            color.frame(height: 18)
            Color.clear.frame(height: 50)
        }
        .frame(width: 84, height: 68)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.cardBorder, lineWidth: 1))
    }
}
