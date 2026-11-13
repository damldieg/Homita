import ActivityKit
import HomitaShared
import SwiftUI
import WidgetKit

/// Live Activity de rutinas: pantalla de bloqueo y Dynamic Island. La cuenta atrás y la barra son
/// del sistema (`timerInterval`), así que avanzan sin que la app esté abierta. Los textos siguen
/// siendo ciertos aunque la actividad no se actualice («Empieza a las 17:30», «Termina a las 18:30»).
struct RoutineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoutineActivityAttributes.self) { context in
            RoutineLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(WidgetTheme.surface)
                .activitySystemActionForegroundColor(WidgetTheme.accent)
                .widgetURL(HomitaDeepLink.rutinas.url)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Color(hex: state.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3.bold())
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: state, isStale: context.isStale)
                        .font(.title3.bold().monospacedDigit())
                        .frame(maxWidth: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(timerInterval: state.progressStart...state.progressEnd, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(tint)
                        Text(RoutineLockScreenView.caption(for: state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(tint)
            } compactTrailing: {
                CountdownText(state: state, isStale: context.isStale)
                    .font(.caption.bold().monospacedDigit())
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(tint)
            }
            .keylineTint(tint)
            .widgetURL(HomitaDeepLink.rutinas.url)
        }
    }
}

/// Cuenta atrás hasta el inicio (aviso) o el fin (en curso); queda en 0:00 al llegar.
private struct CountdownText: View {
    let state: RoutineActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let target = state.progressEnd
        if isStale || Date() >= target {
            Text("0:00")
        } else {
            Text(timerInterval: countdownRange(to: target), pauseTime: target, countsDown: true, showsHours: false)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RoutineLockScreenView: View {
    let state: RoutineActivityAttributes.ContentState
    let isStale: Bool

    private var tint: Color { Color(hex: state.colorHex) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(heading)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isStale ? WidgetTheme.inkSoft : tint)
                        Text(state.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    CountdownText(state: state, isStale: isStale)
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(isStale ? WidgetTheme.inkSoft : WidgetTheme.ink)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                ProgressView(timerInterval: state.progressStart...state.progressEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(tint)
                Text(Self.caption(for: state))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }

    private var heading: String {
        if isStale { return "FINALIZADA" }
        return state.phase == .now ? "EN CURSO" : "PRÓXIMA RUTINA"
    }

    /// «Termina a las 18:30 · 2 de 5 hechas · Después: Baño 20:00».
    static func caption(for state: RoutineActivityAttributes.ContentState) -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        var parts = [state.phase == .now ? "Termina a las \(time.string(from: state.end))"
                                        : "Empieza a las \(time.string(from: state.start))"]
        parts.append("\(state.doneCount) de \(state.totalCount) hechas")
        if let next = state.nextTitle, let nextStart = state.nextStart {
            parts.append("Después: \(next) \(time.string(from: nextStart))")
        }
        return parts.joined(separator: " · ")
    }
}
