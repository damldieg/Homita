import SwiftUI

/// Semana del menú: rejilla día × franjas activas (filas = días, columnas = franjas). Flechas entre
/// semanas, estado borrador/aceptado, aviso rojo por casilla (check), «sin comprobar» cuando el check no
/// puede evaluarla, «fuera» según el horario y nº de eventos.
struct WeekGridView: View {
    @Bindable var store: MealsStore
    let services: AppServices
    /// Avisa a la Compra de lo que entró al aceptar el menú.
    var onShoppingSync: (ShoppingSyncResult) -> Void = { _ in }
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
        .task { await store.load() }
        .errorAlert($store.errorMessage)
        .sheet(item: $slotEditor) { request in
            NavigationStack {
                MealSlotSheet(store: store, recipes: services.recipes, day: request.day, slot: request.slot, item: request.item)
            }
        }
        .sheet(isPresented: Binding(get: { store.acceptPreview != nil }, set: { if !$0 { store.cancelAccept() } })) {
            NavigationStack {
                AcceptShoppingSheet(preview: store.acceptPreview, isWorking: store.isWorking,
                                    onConfirm: { Task { await store.accept() } }, onCancel: { store.cancelAccept() })
            }
        }
        .alert("Compra actualizada", isPresented: Binding(get: { store.acceptedShopping != nil },
                                                           set: { if !$0 { store.acceptedShopping = nil } })) {
            Button("Entendido") { store.acceptedShopping = nil }
        } message: {
            Text(Self.acceptedMessage(store.acceptedShopping))
        }
        .onChange(of: store.acceptedShopping) { _, result in
            if let result { onShoppingSync(result) }
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
                grid
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

    // MARK: Rejilla día × franja

    private static let dayColumnWidth: CGFloat = 52
    private static let scrollColumnWidth: CGFloat = 150

    /// Filas = días de la semana, columnas = franjas activas. Con 1 o 2 franjas reparte el ancho (cabe en
    /// iPhone sin scroll horizontal); con más, columnas de ancho fijo y scroll horizontal.
    @ViewBuilder private var grid: some View {
        let slots = store.enabledSlots
        if slots.count <= 2 {
            gridBody(slots: slots, columnWidth: nil)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                gridBody(slots: slots, columnWidth: Self.scrollColumnWidth)
            }
        }
    }

    private func gridBody(slots: [MealSlot], columnWidth: CGFloat?) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                Color.clear.frame(width: Self.dayColumnWidth, height: 1)
                ForEach(slots) { slot in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(MealSlotKind.title(slot.slot)).font(HomitaFont.inter(13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                        Text(slot.time).font(HomitaFont.inter(11)).foregroundStyle(Palette.inkMuted)
                    }
                    .frame(width: columnWidth, alignment: .leading)
                    .frame(maxWidth: columnWidth == nil ? .infinity : nil, alignment: .leading)
                }
            }
            ForEach(store.days, id: \.self) { day in
                HStack(alignment: .top, spacing: 6) {
                    dayLabel(day).frame(width: Self.dayColumnWidth, alignment: .leading)
                    ForEach(slots) { slot in
                        slotCell(day: day, slot: slot)
                            .frame(width: columnWidth, alignment: .topLeading)
                            .frame(maxWidth: columnWidth == nil ? .infinity : nil, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            legend
        }
    }

    private func dayLabel(_ day: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.dayTitle(day, store.timeZone)).font(HomitaFont.inter(13, weight: .semibold)).foregroundStyle(Palette.ink)
            if let n = store.eventCounts[day], n > 0 {
                Text("\(n) \(n == 1 ? "evento" : "eventos")").font(HomitaFont.inter(10)).foregroundStyle(Palette.inkSoft)
            }
            if store.canEdit {
                Menu {
                    ForEach(store.days.filter { $0 != day }, id: \.self) { other in
                        Button("Copiar a \(Self.dayTitle(other, store.timeZone))") { store.copyDay(from: day, to: other) }
                    }
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 12)) }
                .accessibilityLabel("Copiar día")
            }
        }
    }

    private func slotCell(day: String, slot: MealSlot) -> some View {
        let items = store.items(day: day, slot: slot.slot)
        let out = outNames(day: day, slot: slot.slot)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.key) { item in
                Button { if store.canEdit { slotEditor = SlotEditorRequest(day: day, slot: slot.slot, item: item) } } label: {
                    HStack(alignment: .top, spacing: 4) {
                        statusIcon(item)
                        Text(Self.label(item)).font(HomitaFont.inter(13)).foregroundStyle(Palette.ink)
                            .lineLimit(3).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(store.issues(for: item).isEmpty ? Palette.surface2 : Palette.errSoft, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            if !out.isEmpty {
                Text("Fuera: \(out.joined(separator: ", "))").font(HomitaFont.inter(11)).foregroundStyle(Palette.inkMuted)
            }
            if store.canEdit {
                Button { slotEditor = SlotEditorRequest(day: day, slot: slot.slot, item: nil) } label: {
                    Image(systemName: "plus").font(.system(size: 14)).frame(maxWidth: .infinity, minHeight: 28)
                }
                .foregroundStyle(Palette.accent)
                .accessibilityLabel(items.isEmpty ? "Añadir" : "Otro plato")
                .accessibilityIdentifier("menu.anadir.\(day).\(slot.slot)")
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func statusIcon(_ item: MealPlanItem) -> some View {
        switch store.checkStatus(for: item) {
        case .issues:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Palette.err)
                .accessibilityLabel(issueText(item))
        case .clean:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.ok)
                .accessibilityLabel("Sin avisos (comprobado)")
        case .unchecked:
            Image(systemName: "questionmark.circle").font(.system(size: 12)).foregroundStyle(Palette.warn)
                .accessibilityLabel("Sin comprobar")
        case .notApplicable:
            EmptyView()
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Sin avisos (comprobado)", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.ok)
            Label("Sin comprobar: texto libre, sobras o ingredientes fuera del catálogo", systemImage: "questionmark.circle")
                .foregroundStyle(Palette.warn)
        }
        .font(HomitaFont.inter(11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
        if store.uncheckedCount > 0 {
            Label("\(store.uncheckedCount) \(store.uncheckedCount == 1 ? "casilla sin comprobar" : "casillas sin comprobar"): solo se revisan alergias de recetas con ingredientes del catálogo.",
                  systemImage: "questionmark.circle")
                .font(HomitaFont.inter(13)).foregroundStyle(Palette.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if store.canEdit {
            if store.isDirty {
                HomitaButton(title: "Guardar cambios", isLoading: store.isWorking) { Task { await store.save() } }
                    .accessibilityIdentifier("menu.guardar")
            }
            if store.isDraft, !store.items.isEmpty {
                HomitaButton(title: "Aceptar menú", kind: store.isDirty ? .secondary : .primary, isLoading: store.isWorking) {
                    Task { await store.prepareAccept() }
                }
                .accessibilityIdentifier("menu.aceptar")
            }
        }
    }

    // MARK: Texto

    static func acceptedMessage(_ result: ShoppingSyncResult?) -> String {
        guard let result, !result.isEmpty else { return "La compra ya estaba al día." }
        var parts: [String] = []
        if result.added > 0 { parts.append("\(result.added) \(result.added == 1 ? "artículo nuevo" : "artículos nuevos")") }
        if result.updated > 0 { parts.append("\(result.updated) \(result.updated == 1 ? "cantidad cambiada" : "cantidades cambiadas")") }
        if result.removed > 0 { parts.append("\(result.removed) \(result.removed == 1 ? "artículo quitado" : "artículos quitados")") }
        return parts.joined(separator: ", ").capitalizedFirst + "."
    }

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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Hoja previa a aceptar: lo que entraría en la compra, por sección, y confirmación.
struct AcceptShoppingSheet: View {
    let preview: ShoppingPreview?
    let isWorking: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section {
                if let items = preview?.items, !items.isEmpty {
                    Text("Esto entra en la compra. Después podrás revisar y marcar lo que ya tengas.")
                        .font(HomitaFont.inter(14)).foregroundStyle(Palette.inkSoft)
                    ForEach(items, id: \.aggKey) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label).font(HomitaFont.inter(16, weight: .medium))
                                let dishes = Array(Set(item.sources.compactMap(\.name))).sorted()
                                if !dishes.isEmpty {
                                    Text("Para: " + dishes.joined(separator: ", "))
                                        .font(HomitaFont.inter(13)).foregroundStyle(Palette.inkSoft)
                                }
                            }
                            Spacer()
                            Text(item.quantityText).foregroundStyle(Palette.inkSoft)
                        }
                    }
                } else {
                    Text("Este menú no añade ingredientes a la compra.")
                        .font(HomitaFont.inter(15)).foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .navigationTitle("Aceptar menú")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Aceptar", action: onConfirm)
                    .disabled(isWorking)
                    .accessibilityIdentifier("menu.aceptar.confirmar")
            }
        }
    }
}
