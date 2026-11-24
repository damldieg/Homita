import SwiftUI

/// Semana del menú: un bloque por día con una fila por franja activa. Flechas entre semanas, estado
/// borrador/aceptado, aviso rojo por casilla (check), «fuera» según el horario y nº de eventos.
struct WeekGridView: View {
    @Bindable var store: MealsStore
    let services: AppServices
    @State private var slotEditor: SlotEditorRequest?
    @State private var copySource: String?
    @State private var confirmArchive = false

    struct SlotEditorRequest: Identifiable {
        let day: String
        let slot: String
        let item: MealPlanItem?
        var id: String { item?.key ?? "new-\(day)-\(slot)" }
    }

    var body: some View {
        Group {
            if store.profile == nil, case .failed(let message) = store.state {
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                    HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.load() } }
                }
                .padding(24)
            } else if store.profile == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .task { if store.state == .idle { await store.load() } }
        .errorAlert($store.errorMessage)
        .sheet(item: $slotEditor) { request in
            NavigationStack {
                MealSlotSheet(store: store, recipes: services.recipes, day: request.day, slot: request.slot, item: request.item)
            }
        }
        .homitaConfirm("¿Archivar el menú de esta semana?", isPresented: $confirmArchive, confirmTitle: "Archivar") {
            Task { await store.archive() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                weekHeader
                if let notice = store.notice {
                    Text(notice).font(HomitaFont.inter(14)).foregroundStyle(Palette.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Palette.warnSoft, in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { store.notice = nil }
                }
                if store.state == .loading { ProgressView() }
                ForEach(store.days, id: \.self) { day in dayCard(day) }
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await store.load() }
    }

    // MARK: Cabecera

    private var weekHeader: some View {
        HStack(spacing: 8) {
            Button { Task { await store.shiftWeek(by: -1) } } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Semana anterior")
            VStack(spacing: 2) {
                Text(weekTitle).font(HomitaFont.inter(16, weight: .semibold)).foregroundStyle(Palette.ink)
                statusBadge
            }
            .frame(maxWidth: .infinity)
            .onTapGesture { Task { await store.goToCurrentWeek() } }
            Button { Task { await store.shiftWeek(by: 1) } } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Semana siguiente")
            menu
        }
        .padding(.vertical, 4)
    }

    private var weekTitle: String {
        guard let first = store.days.first, let last = store.days.last else { return "" }
        return "\(Self.short(first, store.timeZone)) – \(Self.short(last, store.timeZone))"
    }

    @ViewBuilder private var statusBadge: some View {
        if store.isDirty {
            Text("Sin guardar").font(HomitaFont.inter(12, weight: .semibold)).foregroundStyle(Palette.warn)
        } else if store.isAccepted {
            Text("Aceptado").font(HomitaFont.inter(12, weight: .semibold)).foregroundStyle(Palette.ok)
        } else {
            Text(store.plan == nil ? "Sin menú" : "Borrador").font(HomitaFont.inter(12, weight: .semibold)).foregroundStyle(Palette.inkSoft)
        }
    }

    private var menu: some View {
        Menu {
            if store.plan == nil {
                Button("Repetir semana pasada", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.repeatPreviousWeek() }
                }
            }
            if store.isDirty {
                Button("Descartar cambios", systemImage: "arrow.uturn.backward") { store.discardChanges() }
            }
            if store.plan != nil {
                Button("Archivar semana", systemImage: "archivebox", role: .destructive) { confirmArchive = true }
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("Más acciones")
    }

    // MARK: Día

    private func dayCard(_ day: String) -> some View {
        HomitaCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Self.dayTitle(day, store.timeZone)).font(HomitaFont.inter(16, weight: .semibold)).foregroundStyle(Palette.ink)
                    if let n = store.eventCounts[day], n > 0 {
                        Text("\(n) \(n == 1 ? "evento" : "eventos")").font(HomitaFont.inter(12)).foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    if store.canEdit {
                        Menu {
                            ForEach(store.days.filter { $0 != day }, id: \.self) { other in
                                Button("Copiar a \(Self.dayTitle(other, store.timeZone))") { store.copyDay(from: day, to: other) }
                            }
                        } label: { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("Copiar día")
                    }
                }
                ForEach(store.enabledSlots) { slot in slotRow(day: day, slot: slot) }
            }
        }
    }

    private func slotRow(day: String, slot: MealSlot) -> some View {
        let items = store.items(day: day, slot: slot.slot)
        let out = outNames(day: day, slot: slot.slot)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(MealSlotKind.title(slot.slot)).font(HomitaFont.inter(13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                Text(slot.time).font(HomitaFont.inter(12)).foregroundStyle(Palette.inkMuted)
                Spacer()
                if !out.isEmpty {
                    Text("Fuera: \(out.joined(separator: ", "))").font(HomitaFont.inter(12)).foregroundStyle(Palette.inkMuted)
                }
            }
            ForEach(items, id: \.key) { item in
                Button { if store.canEdit { slotEditor = SlotEditorRequest(day: day, slot: slot.slot, item: item) } } label: {
                    HStack(spacing: 6) {
                        if !store.issues(for: item).isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.err)
                                .accessibilityLabel(issueText(item))
                        }
                        Text(Self.label(item)).font(HomitaFont.inter(16)).foregroundStyle(Palette.ink).lineLimit(2)
                        Spacer()
                    }
                    .padding(10)
                    .background(store.issues(for: item).isEmpty ? Palette.surface2 : Palette.errSoft, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            if store.canEdit {
                Button { slotEditor = SlotEditorRequest(day: day, slot: slot.slot, item: nil) } label: {
                    Label(items.isEmpty ? "Añadir" : "Otro plato", systemImage: "plus").font(HomitaFont.inter(14))
                }
                .foregroundStyle(Palette.accent)
                .accessibilityIdentifier("menu.anadir.\(day).\(slot.slot)")
            }
        }
    }

    private func outNames(day: String, slot: String) -> [String] {
        (store.profile?.members ?? []).filter { store.isOut(memberId: $0.homeMemberId, day: day, slot: slot) }.map(\.name)
    }

    private func issueText(_ item: MealPlanItem) -> String {
        store.issues(for: item).map { Self.issueDescription($0, members: store.profile?.members ?? []) }.joined(separator: ". ")
    }

    // MARK: Acciones

    @ViewBuilder private var actions: some View {
        if !store.issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(store.issues.enumerated()), id: \.offset) { _, issue in
                    Label(Self.issueDescription(issue, members: store.profile?.members ?? []), systemImage: "exclamationmark.triangle.fill")
                        .font(HomitaFont.inter(14)).foregroundStyle(Palette.err)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if store.canEdit {
            if store.isDirty {
                HomitaButton(title: "Guardar cambios", isLoading: store.isWorking) { Task { await store.save() } }
                    .accessibilityIdentifier("menu.guardar")
            }
            if store.isDraft, !store.items.isEmpty {
                HomitaButton(title: "Aceptar menú", kind: store.isDirty ? .secondary : .primary, isLoading: store.isWorking) {
                    Task { await store.accept() }
                }
                .accessibilityIdentifier("menu.aceptar")
            }
        }
    }

    // MARK: Texto

    static func label(_ item: MealPlanItem) -> String {
        switch item.kind {
        case "leftovers": return item.title.isEmpty ? "Sobras" : "Sobras: \(item.title)"
        case "eat_out": return item.title.isEmpty ? "Comer fuera" : "Fuera: \(item.title)"
        default: return item.title.isEmpty ? "Sin título" : item.title
        }
    }

    static func issueDescription(_ issue: MealIssue, members: [MealMember]) -> String {
        let who = members.first { Int64($0.homeMemberId) == issue.memberId }?.name ?? "Alguien"
        switch issue.code {
        case "allergen": return "\(who): alérgeno \(issue.detail["allergen"] ?? "") en \(issue.detail["ingredient"] ?? "un ingrediente")"
        case "intolerance": return "\(who): intolerancia a \(issue.detail["ingredient"] ?? "un ingrediente")"
        case "diet": return "\(who): no encaja con su dieta (\(issue.detail["ingredient"] ?? ""))"
        case "member_out": return "\(who) está fuera en esta franja"
        default: return "\(who): revisa esta casilla"
        }
    }

    static func dayTitle(_ day: String, _ tz: TimeZone) -> String {
        guard let date = MealWeek.date(day, timeZone: tz) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: date).capitalized
    }

    static func short(_ day: String, _ tz: TimeZone) -> String {
        guard let date = MealWeek.date(day, timeZone: tz) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }
}
