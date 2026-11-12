import SwiftUI

/// Tarjeta «Rutinas de hoy» de Inicio: progreso, pendientes (la siguiente destacada) y
/// completadas plegables. Marcar/desmarcar usa el estado local de `InicioStore`.
struct RoutinesTodayCard: View {
    let store: InicioStore
    let dateText: String
    let onOpenAll: () -> Void

    @State private var showDone = true

    private var routines: [RoutineEntry] { store.todayRoutinesByTime }
    private var pending: [RoutineEntry] { routines.filter { !store.isRoutineDone($0) } }
    private var done: [RoutineEntry] { routines.filter { store.isRoutineDone($0) } }
    private var percent: Int { routines.isEmpty ? 0 : Int((Double(done.count) / Double(routines.count) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch store.routinesState {
            case .idle where routines.isEmpty, .loading where routines.isEmpty:
                emptyText("Cargando…")
            case .failed(let message):
                Text(message)
                    .font(HomitaFont.geist(15, relativeTo: .body))
                    .foregroundStyle(Palette.accent)
                HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.loadRoutines() } }
            default:
                if routines.isEmpty {
                    emptyText("Sin rutinas hoy")
                } else {
                    progress
                    pendingList
                    if !done.isEmpty { doneSection }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.cardBorder, lineWidth: 1))
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Rutinas de hoy")
                    .font(HomitaFont.geist(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(dateText)
                    .font(HomitaFont.geist(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpenAll) {
                HStack(spacing: 2) {
                    Text("Ver todas")
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .font(HomitaFont.geist(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver todas las rutinas")
        }
    }

    // MARK: - Progreso

    private var progress: some View {
        let left = pending.count
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(done.count) de \(routines.count) hechas")
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(left == 0 ? "¡Completo!" : (left == 1 ? "Falta 1" : "Faltan \(left)"))
                    .font(HomitaFont.geist(13, weight: .bold, relativeTo: .footnote))
                    .foregroundStyle(Palette.accent)
            }
            .font(HomitaFont.geist(13, weight: .medium, relativeTo: .footnote))
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

    // MARK: - Pendientes

    private var pendingList: some View {
        VStack(spacing: 8) {
            ForEach(Array(pending.enumerated()), id: \.element.id) { index, routine in
                pendingRow(routine, isNext: index == 0)
            }
            if pending.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .semibold))
                    Text("Todo hecho por hoy")
                        .font(HomitaFont.geist(15, weight: .semibold, relativeTo: .body))
                }
                .foregroundStyle(Color(hex: "#2F5E3B"))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.online.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func pendingRow(_ routine: RoutineEntry, isNext: Bool) -> some View {
        let status = store.status(for: routine)
        return VStack(alignment: .leading, spacing: 4) {
            if isNext {
                Text("SIGUIENTE\(countdownSuffix(routine))")
                    .font(HomitaFont.geist(11, weight: .bold, relativeTo: .caption2))
                    .tracking(0.7)
                    .foregroundStyle(Palette.accent)
                    .padding(.leading, 4)
            }
            HStack(spacing: 4) {
                RoutineRow(routine: routine, next: nil, status: status, embedded: true) {}
                    .disabled(status == .expired)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.setRoutineDone(routine, done: true) }
                } label: {
                    Circle()
                        .strokeBorder(Palette.inkMuted, lineWidth: 2)
                        .background(Circle().fill(.white))
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Marcar \(routine.title) como hecha")
            }
        }
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
                .font(HomitaFont.geist(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 4)
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
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.setRoutineDone(routine, done: false) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Palette.online, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Desmarcar \(routine.title)")
            RoutineRow(routine: routine, next: nil, status: store.status(for: routine), embedded: true) {}
                .disabled(true)
        }
    }

    // MARK: - Piezas

    /// Sufijo « · en N min» de la siguiente si empieza en menos de 3 horas.
    private func countdownSuffix(_ routine: RoutineEntry) -> String {
        if let minutes = store.minutesUntilStart(of: routine), minutes > 0, minutes < 180 {
            return " · EN \(minutes) MIN"
        }
        return ""
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(HomitaFont.geist(15, relativeTo: .body))
            .foregroundStyle(Palette.inkSoft)
    }
}
