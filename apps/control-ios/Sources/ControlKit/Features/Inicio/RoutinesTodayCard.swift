import SwiftUI

/// Tarjeta «Rutinas de hoy» de Inicio (E1-04, diseño del usuario). El estado sale solo del horario
/// (D-1: sin marca manual): aún no empieza, aviso (≤ 60 min), en curso (ventana de 60 min) y
/// finalizada, que pasa sola a «completadas». Con dos o más activas a la vez, variante compacta.
struct RoutinesTodayCard: View {
    let store: InicioStore
    let dateText: String
    let onOpenAll: () -> Void

    @State private var showDone = true

    /// Fase de cada rutina según el store (D-1: solo horario).
    private func phase(_ routine: RoutineEntry) -> InicioStore.RoutinePhase {
        store.phase(of: routine)
    }

    private var routines: [RoutineEntry] { store.todayRoutinesByTime }
    private var done: [RoutineEntry] { routines.filter { phase($0) == .done } }
    private var inProgress: [RoutineEntry] { routines.filter { phase($0) == .now } }
    /// Activas = en curso o en aviso; se muestran arriba.
    private var active: [RoutineEntry] { routines.filter { [.now, .soon].contains(phase($0)) } }
    private var later: [RoutineEntry] { routines.filter { phase($0) == .later } }
    private var pendingCount: Int { routines.count - done.count }
    private var percent: Int { routines.isEmpty ? 0 : Int((Double(done.count) / Double(routines.count) * 100).rounded()) }
    /// Dos o más activas a la vez: anillo en lugar de barra (wireframe «Rutinas de hoy», estado 7).
    private var isCompact: Bool { active.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().overlay(Palette.line)
            switch store.routinesState {
            case .idle where routines.isEmpty, .loading where routines.isEmpty:
                HomitaSkeletonRows(count: 2, height: 56, label: "Cargando rutinas")
            case .failed(let message):
                Text(message)
                    .font(HomitaFont.inter(15, relativeTo: .body))
                    .foregroundStyle(Palette.accent)
                HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.loadRoutines() } }
            default:
                if routines.isEmpty {
                    HomitaEmptyNote(text: HomitaEmptyNoteText.todayRoutines)
                } else {
                    progress
                    if pendingCount == 0 {
                        allDone
                    } else {
                        activeSection
                        laterSection
                    }
                    if !done.isEmpty { doneSection }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s5)
        .padding(.bottom, Spacing.s3)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.line, lineWidth: 1))
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Rutinas de hoy")
                    .font(HomitaFont.inter(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(dateText)
                    .font(HomitaFont.inter(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpenAll) {
                HStack(spacing: 2) {
                    Text("Ver todas")
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver todas las rutinas")
        }
    }

    // MARK: - Progreso

    /// «Ahora: <título>», «N en curso», «Falta 1», «Faltan N» o «¡Completo!».
    private var progressLabel: String {
        if pendingCount == 0 { return "¡Completo!" }
        if inProgress.count == 1, let only = inProgress.first { return "Ahora: \(only.title)" }
        if inProgress.count > 1 { return "\(inProgress.count) en curso" }
        return pendingCount == 1 ? "Falta 1" : "Faltan \(pendingCount)"
    }

    private var progress: some View {
        VStack(spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(done.count) de \(routines.count) hechas")
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(progressLabel)
                    .font(HomitaFont.inter(13, weight: .bold, relativeTo: .footnote))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
            }
            .font(HomitaFont.inter(13, weight: .medium, relativeTo: .footnote))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line.opacity(0.6))
                    Capsule().fill(Palette.accent)
                        .frame(width: proxy.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.25), value: percent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progreso de rutinas")
            .accessibilityValue("\(percent) por ciento")
        }
    }

    private var allDone: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .semibold))
            Text("Todo hecho por hoy")
                .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .body))
        }
        .foregroundStyle(Palette.ok)
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.okSoft, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Activas (aviso y en curso)

    @ViewBuilder
    private var activeSection: some View {
        if !active.isEmpty {
            VStack(spacing: Spacing.s2) {
                ForEach(active) { routine in
                    if isCompact {
                        compactRow(routine)
                    } else {
                        activeRow(routine)
                    }
                }
            }
        }
    }

    /// Fila grande con barra de tiempo: aviso (ámbar) o en curso (verde con pulso).
    private func activeRow(_ routine: RoutineEntry) -> some View {
        let isNow = phase(routine) == .now
        let tint = isNow ? Palette.now : Palette.soonText
        let fill = isNow ? Palette.now : Palette.soonFill
        let track = isNow ? Palette.nowTrack : Palette.soonTrack
        let background = isNow ? Palette.nowBg : Palette.soonBg
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Text(isNow ? "✱" : "⚠")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    kicker(isNow ? "En curso" : "Empieza en \(durationText(store.minutesUntilStart(of: routine) ?? 0))",
                           tint: tint, pulse: isNow)
                    Text(routine.title)
                        .font(HomitaFont.inter(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    AssignedPersonsLine(persons: routine.persons)
                }
                Spacer(minLength: Spacing.s2)
                Text(timeText(routine))
                    .font(HomitaFont.inter(15, weight: .bold, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
            }
            meter(fraction: store.windowFraction(of: routine) ?? 0, fill: fill, track: track,
                  left: "Empieza a las \(timeText(routine))",
                  right: isNow ? "Quedan \(store.minutesLeftInWindow(of: routine) ?? 0) min"
                               : "Faltan \(store.minutesUntilStart(of: routine) ?? 0) min",
                  textTint: tint)
        }
        .padding(Spacing.s4)
        .background(background, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    /// Variante compacta con anillo (2 o más activas a la vez).
    private func compactRow(_ routine: RoutineEntry) -> some View {
        let isNow = phase(routine) == .now
        let tint = isNow ? Palette.now : Palette.soonStrong
        let fraction = store.windowFraction(of: routine) ?? 0
        let right = isNow
            ? "Quedan \(store.minutesLeftInWindow(of: routine) ?? 0) min"
            : "Empieza en \(store.minutesUntilStart(of: routine) ?? 0) min"
        return HStack(spacing: Spacing.s3) {
            ZStack {
                Circle().stroke(isNow ? Palette.nowTrack : Palette.soonTrack, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                    .stroke(isNow ? Palette.now : Palette.soonFill, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("✱").font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.title)
                    .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                AssignedPersonsLine(persons: routine.persons)
            }
            Spacer(minLength: Spacing.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeText(routine))
                    .font(HomitaFont.inter(14, weight: .bold, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                Text(right)
                    .font(HomitaFont.inter(12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(tint)
            }
        }
        .padding(Spacing.s3)
        .background(isNow ? Palette.nowBg : Palette.soonBg, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Más tarde

    @ViewBuilder
    private var laterSection: some View {
        if !later.isEmpty {
            VStack(spacing: Spacing.s2) {
                ForEach(Array(later.enumerated()), id: \.element.id) { index, routine in
                    laterRow(routine, isNext: index == 0 && routine.hasFixedTime)
                }
            }
        }
    }

    /// Fila sin barra: «Siguiente» solo en la primera de las que aún no empiezan.
    private func laterRow(_ routine: RoutineEntry, isNext: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Text("✱")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                if isNext, let minutes = store.minutesUntilStart(of: routine) {
                    kicker("Siguiente · en \(durationText(minutes))", tint: Palette.accent, pulse: false)
                }
                Text(routine.title)
                    .font(HomitaFont.inter(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                AssignedPersonsLine(persons: routine.persons)
            }
            Spacer(minLength: Spacing.s2)
            Text(routine.hasFixedTime ? timeText(routine) : "Sin hora")
                .font(HomitaFont.inter(15, weight: .bold, relativeTo: .body))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(Spacing.s3)
        .background(Palette.farBg, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Completadas

    private var doneSection: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.line)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showDone.toggle() }
            } label: {
                HStack {
                    Text(done.count == 1 ? "1 completada" : "\(done.count) completadas")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showDone ? 180 : 0))
                }
                .font(HomitaFont.inter(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, Spacing.s1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showDone ? "Desplegado" : "Plegado")
            if showDone {
                ForEach(done) { routine in doneRow(routine) }
            }
        }
    }

    private func doneRow(_ routine: RoutineEntry) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Palette.onFill)
                .frame(width: 26, height: 26)
                .background(Palette.ok, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.title)
                    .font(HomitaFont.inter(15, relativeTo: .body))
                    .foregroundStyle(Palette.inkMuted)
                    .strikethrough()
                AssignedPersonsLine(persons: routine.persons)
            }
            Spacer(minLength: Spacing.s2)
            Text(timeText(routine))
                .font(HomitaFont.inter(14, relativeTo: .body))
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.horizontal, Spacing.s1)
        .padding(.vertical, Spacing.s2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Piezas

    private func kicker(_ text: String, tint: Color, pulse: Bool) -> some View {
        HStack(spacing: Spacing.s2) {
            if pulse { PulseDot(color: tint) }
            Text(text)
                .font(HomitaFont.inter(11, weight: .bold, relativeTo: .caption2))
                .tracking(0.7)
                .foregroundStyle(tint)
        }
    }

    private func meter(fraction: Double, fill: Color, track: Color, left: String, right: String, textTint: Color) -> some View {
        VStack(spacing: Spacing.s1) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(fill)
                        .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
            HStack {
                Text(left)
                Spacer()
                Text(right).fontWeight(.bold)
            }
            .font(HomitaFont.inter(12, relativeTo: .caption))
            .foregroundStyle(textTint)
        }
        .accessibilityElement(children: .combine)
    }

    /// Hora `HH:mm` de la rutina (sin segundos).
    private func timeText(_ routine: RoutineEntry) -> String {
        String(routine.time.prefix(5))
    }

    /// «N min» o «H h M min» (E1-02/E1-04).
    private func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// Punto con pulso para «En curso». Sin animación con Reduce Motion (E1-07).
private struct PulseDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(pulsing && !reduceMotion ? 1.35 : 1)
            .opacity(pulsing && !reduceMotion ? 0.6 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulsing = true }
            }
            .accessibilityHidden(true)
    }
}
