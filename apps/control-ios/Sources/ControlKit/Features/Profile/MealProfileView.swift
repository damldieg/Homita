import SwiftUI

/// Ajustes › Perfil de hogar (0043). Primer paso con las 7 preguntas de arranque (A1, A2, B1, B5,
/// D1, D2 simple, E1 simple; B1 obligatoria, el resto con «Ahora no») y después el formulario por
/// bloques. Sin B3/B4 (fuera del piloto). Con `menu.profile.edit` se edita todo; sin él, cada persona
/// con cuenta edita solo su bloque C (gustos).
struct MealProfileView: View {
    @State private var store: MealProfileStore
    @State private var showStart = false
    @State private var didAutoStart = false

    init(services: AppServices) {
        _store = State(initialValue: MealProfileStore(
            meals: services.meals, activeHomeId: { services.homeContext.activeHomeId }))
    }

    var body: some View {
        Group {
            if let profile = store.profile {
                form(profile)
            } else if case .failed(let message) = store.state {
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                    HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.load() } }
                }
                .padding(24)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Perfil de hogar")
        .errorAlert($store.errorMessage)
        .task {
            await store.load()
            if store.needsStart, store.profile?.canEdit == true, !didAutoStart {
                didAutoStart = true
                showStart = true
            }
        }
        .sheet(isPresented: $showStart) {
            if let profile = store.profile {
                NavigationStack { MealStartView(store: store, profile: profile) { showStart = false } }
            }
        }
    }

    private func form(_ profile: MealProfile) -> some View {
        List {
            if store.needsStart && profile.canEdit {
                Section {
                    Button("Empezar: 7 preguntas") { showStart = true }
                        .accessibilityIdentifier("comidas.empezar")
                } footer: {
                    Text("Con esto Kito ya puede proponer el primer menú. El resto lo puedes rellenar cuando quieras.")
                }
            }
            if !profile.canEdit {
                Section { Text("Solo puedes editar tus gustos. El resto lo cambian los adultos del hogar.") }
            }
            comensales(profile)
            salud(profile)
            gustos(profile)
            semana(profile)
            cocina(profile)
            estilo(profile)
            compra(profile)
            paises(profile)
        }
        .disabled(store.state == .loading && store.profile == nil)
    }

    // MARK: - A. Comensales

    private func comensales(_ profile: MealProfile) -> some View {
        Section("A. Comensales") {
            ForEach(store.candidates, id: \.id) { member in
                let eats = store.member(member.id) != nil
                Toggle(member.name, isOn: Binding(
                    get: { eats }, set: { value in Task { await store.setEats(member, value) } }))
                    .disabled(!profile.canEdit)
                if let meal = store.member(member.id) {
                    Picker("Edad de \(member.name)", selection: Binding(
                        get: { meal.ageBand },
                        set: { v in Task { await store.updateMember(MealMemberUpdate(homeMemberId: member.id, ageBand: v)) } })) {
                        ForEach(MealRules.ageBands, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .disabled(!profile.canEdit)
                }
            }
        }
    }

    // MARK: - B. Salud y restricciones (sin B3/B4)

    private func salud(_ profile: MealProfile) -> some View {
        Section {
            ForEach(profile.members) { meal in
                NavigationLink(meal.name) { MealHealthView(store: store, member: meal, canEdit: profile.canEdit) }
            }
        } header: {
            Text("B. Salud y restricciones")
        } footer: {
            Text("Alergias, dieta y objetivos de cada persona. Son restricciones duras: Kito nunca las incumple.")
        }
    }

    // MARK: - C. Gustos (cada persona con cuenta edita los suyos)

    private func gustos(_ profile: MealProfile) -> some View {
        Section("C. Gustos") {
            ForEach(profile.members) { meal in
                if profile.canEdit || meal.isMe {
                    NavigationLink(meal.isMe ? "\(meal.name) (tú)" : meal.name) { MealTasteView(store: store, member: meal) }
                }
            }
        }
    }

    // MARK: - D. Semana tipo

    private func semana(_ profile: MealProfile) -> some View {
        Section {
            ForEach(profile.slots) { slot in
                HStack {
                    Toggle(MealRules.label(slot.slot, in: MealRules.slots) ?? slot.slot, isOn: Binding(
                        get: { slot.enabled }, set: { v in save(slots: profile.slots, slot.slot) { $0.enabled = v } }))
                    if slot.enabled {
                        DatePicker("", selection: Binding(
                            get: { Self.date(slot.time) },
                            set: { d in save(slots: profile.slots, slot.slot) { $0.time = Self.hhmm(d) } }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                .disabled(!profile.canEdit)
            }
            Picker("Día de compra", selection: homeBinding(profile.profile.shoppingDay) { MealHomeUpdate(shoppingDay: $0) }) {
                ForEach(MealRules.weekdays, id: \.0) { Text($0.1).tag($0.0) }
            }
            .disabled(!profile.canEdit)
            Text("Días que coméis fuera").font(.footnote).foregroundStyle(Palette.inkSoft)
            MealOutModes(selected: MealRules.outModes(profile), slots: profile.slots, enabled: profile.canEdit) { modes in
                Task { await store.setOutModes(modes) }
            }
        } header: {
            Text("D. Semana tipo")
        } footer: {
            Text("Hora local del hogar (\(profile.timezone)).")
        }
    }

    // MARK: - E. Cocina

    private func cocina(_ profile: MealProfile) -> some View {
        Section("E. Cocina") {
            optionalPicker("Tiempo entre semana", profile.profile.cookMinutesWeekday, MealRules.cookMinutes, profile.canEdit) {
                MealHomeUpdate(cookMinutesWeekday: $0)
            }
            optionalPicker("Tiempo en fin de semana", profile.profile.cookMinutesWeekend, MealRules.cookMinutes, profile.canEdit) {
                MealHomeUpdate(cookMinutesWeekend: $0)
            }
            optionalPicker("Nivel de cocina", profile.profile.cookSkill, MealRules.skills, profile.canEdit) {
                MealHomeUpdate(cookSkill: $0)
            }
            optionalPicker("Congelador", profile.profile.freezerSpace, MealRules.freezer, profile.canEdit) {
                MealHomeUpdate(freezerSpace: $0)
            }
            DisclosureGroup("Equipamiento") {
                ForEach(MealRules.equipment, id: \.0) { item in
                    Toggle(item.1, isOn: Binding(
                        get: { profile.profile.equipment.contains(item.0) },
                        set: { on in
                            var list = profile.profile.equipment.filter { $0 != item.0 }
                            if on { list.append(item.0) }
                            Task { await store.updateHome(MealHomeUpdate(equipment: list)) }
                        }))
                        .disabled(!profile.canEdit)
                }
            }
        }
    }

    // MARK: - F. Estilo

    private func estilo(_ profile: MealProfile) -> some View {
        Section("F. Estilo y variedad") {
            optionalPicker("Repetición", profile.profile.repeatPolicy, MealRules.repeatPolicies, profile.canEdit) {
                MealHomeUpdate(repeatPolicy: $0)
            }
            optionalPicker("Sobras", profile.profile.leftovers, MealRules.leftovers, profile.canEdit) {
                MealHomeUpdate(leftovers: $0)
            }
            optionalPicker("Postre", profile.profile.dessert, MealRules.desserts, profile.canEdit) {
                MealHomeUpdate(dessert: $0)
            }
        }
    }

    // MARK: - G. Compra

    private func compra(_ profile: MealProfile) -> some View {
        Section {
            MealBudgetField(value: profile.profile.budgetWeekly, enabled: profile.canEdit) { v in
                Task { await store.updateHome(MealHomeUpdate(budgetWeekly: v)) }
            }
            Toggle("Agrupar por sección", isOn: Binding(
                get: { profile.profile.groupBySection },
                set: { v in Task { await store.updateHome(MealHomeUpdate(groupBySection: v)) } }))
                .disabled(!profile.canEdit)
        } header: {
            Text("G. Compra")
        } footer: {
            Text("El presupuesto semanal es orientativo (€).")
        }
    }

    // MARK: - H. Países

    private func paises(_ profile: MealProfile) -> some View {
        let selected = profile.profile.countries
        return Section {
            NavigationLink {
                MealCountriesView(store: store, canEdit: profile.canEdit)
            } label: {
                HStack {
                    Text("Países")
                    Spacer()
                    Text(selected.isEmpty ? "Ninguno" : selected.map(MealCountries.flag).joined(separator: " "))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .accessibilityIdentifier("comidas.paises")
        } header: {
            Text("H. Países")
        } footer: {
            Text("Kito propondrá platos de estos países. Puedes elegir varios, por ejemplo si en casa hay dos nacionalidades.")
        }
    }

    // MARK: - Helpers

    private func homeBinding<T>(_ value: T, _ make: @escaping (T) -> MealHomeUpdate) -> Binding<T> {
        Binding(get: { value }, set: { v in Task { await store.updateHome(make(v)) } })
    }

    private func optionalPicker<T: Hashable>(_ title: String, _ value: T?, _ options: [(T, String)], _ canEdit: Bool,
                                              _ make: @escaping (T) -> MealHomeUpdate) -> some View {
        Picker(title, selection: Binding<T?>(
            get: { value }, set: { v in if let v { Task { await store.updateHome(make(v)) } } })) {
            Text("Sin definir").tag(T?.none)
            ForEach(options, id: \.0) { Text($0.1).tag(Optional($0.0)) }
        }
        .disabled(!canEdit)
    }

    private func save(slots: [MealSlot], _ key: String, _ change: (inout MealSlot) -> Void) {
        guard var slot = slots.first(where: { $0.slot == key }) else { return }
        change(&slot)
        Task { await store.setSlots([slot]) }
    }

    static func date(_ time: String) -> Date {
        let minutes = MealRules.minutes(fromTime: time) ?? 0
        return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return MealRules.time(fromMinutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

/// Selector múltiple de países (lista cerrada, nombre en español y bandera). Cada cambio guarda la lista.
struct MealCountriesView: View {
    let store: MealProfileStore
    let canEdit: Bool

    private var selected: [String] { store.profile?.profile.countries ?? [] }

    var body: some View {
        List {
            ForEach(MealCountries.sorted, id: \.self) { code in
                let on = selected.contains(code)
                Button {
                    Task { await store.setCountries(on ? selected.filter { $0 != code } : selected + [code]) }
                } label: {
                    HStack {
                        Text(MealCountries.label(code)).foregroundStyle(Palette.ink)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                    }
                }
                .disabled(!canEdit)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .navigationTitle("Países")
        .errorAlert(Binding(get: { store.errorMessage }, set: { store.errorMessage = $0 }))
    }
}

/// Un selector por día: día completo, solo comida, solo cena o ninguno (D2).
/// Las opciones de una franja no activa quedan ocultas.
private struct MealOutModes: View {
    let selected: [Int: OutMode]
    let slots: [MealSlot]
    let enabled: Bool
    let onChange: ([Int: OutMode]) -> Void

    private func options(current: OutMode) -> [OutMode] {
        let active = Set(slots.filter(\.enabled).map(\.slot))
        return OutMode.allCases.filter {
            current == $0 || ($0 != .lunch || active.contains("lunch")) && ($0 != .dinner || active.contains("dinner"))
        }
    }

    var body: some View {
        ForEach(MealRules.weekdays, id: \.0) { day in
            let current = selected[day.0] ?? .none
            Picker(day.1, selection: Binding(
                get: { current },
                set: { mode in
                    var next = selected
                    next[day.0] = mode
                    onChange(next)
                })) {
                ForEach(options(current: current), id: \.self) { Text($0.label) }
            }
            .pickerStyle(.menu)
            .disabled(!enabled)
        }
    }
}

private struct MealBudgetField: View {
    let value: Double?
    let enabled: Bool
    let onCommit: (Double) -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            Text("Presupuesto semanal (€)")
            Spacer()
            TextField("Sin definir", text: $text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .disabled(!enabled)
                .onSubmit { if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v >= 0 { onCommit(v) } }
        }
        .onAppear { text = value.map { String(format: "%g", $0) } ?? "" }
    }
}

/// B1+B2, B5, B6 de una persona.
struct MealHealthView: View {
    let store: MealProfileStore
    let member: MealMember
    let canEdit: Bool

    private var current: MealMember { store.member(member.homeMemberId) ?? member }

    var body: some View {
        List {
            Section {
                ForEach(MealRules.allergens, id: \.0) { item in
                    let entry = current.allergies.first { $0.allergen == item.0 }
                    Toggle(item.1, isOn: Binding(
                        get: { entry != nil }, set: { on in saveAllergies(toggling: item.0, on: on) }))
                    if let entry {
                        Picker("Gravedad", selection: Binding(
                            get: { entry.severity }, set: { v in saveAllergies(severity: v, for: item.0) })) {
                            ForEach(MealRules.severities, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                }
                Toggle("No tiene alergias", isOn: Binding(
                    get: { current.allergiesAnswered && current.allergies.isEmpty },
                    set: { on in
                        if on {
                            Task { await store.updateMember(MealMemberUpdate(
                                homeMemberId: member.homeMemberId, allergiesAnswered: true, allergies: [])) }
                        }
                    }))
            } header: {
                Text("B1. Alergias (obligatoria)")
            } footer: {
                Text("Marca «No tiene alergias» si ninguna. Kito descarta el plato entero si alguien alérgico come ese día.")
            }
            Section("B5. Dieta") {
                Picker("Dieta", selection: Binding(
                    get: { current.diet },
                    set: { v in Task { await store.updateMember(MealMemberUpdate(homeMemberId: member.homeMemberId, diet: v)) } })) {
                    ForEach(MealRules.diets, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
            Section("B6. Objetivos") {
                ForEach(MealRules.goals, id: \.0) { item in
                    Toggle(item.1, isOn: Binding(
                        get: { current.goals.contains(item.0) },
                        set: { on in
                            var goals = current.goals.filter { $0 != item.0 }
                            if on { goals.append(item.0) }
                            Task { await store.updateMember(MealMemberUpdate(homeMemberId: member.homeMemberId, goals: goals)) }
                        }))
                }
            }
        }
        .disabled(!canEdit)
        .navigationTitle(member.name)
    }

    private func saveAllergies(toggling code: String, on: Bool) {
        var list = current.allergies.filter { $0.allergen != code }
        if on { list.append(MealAllergy(allergen: code, severity: "avoid_ingredient")) }
        Task { await store.updateMember(MealMemberUpdate(
            homeMemberId: member.homeMemberId, allergiesAnswered: true, allergies: list)) }
    }

    private func saveAllergies(severity: String, for code: String) {
        let list = current.allergies.map { $0.allergen == code ? MealAllergy(allergen: code, severity: severity, note: $0.note) : $0 }
        Task { await store.updateMember(MealMemberUpdate(
            homeMemberId: member.homeMemberId, allergiesAnswered: true, allergies: list)) }
    }
}

/// C1–C4 de una persona: lo edita ella misma o quien tenga `menu.profile.edit`.
struct MealTasteView: View {
    let store: MealProfileStore
    let member: MealMember
    @State private var dislikes = ""
    @State private var favorites = ""
    @State private var quirks = ""

    var body: some View {
        List {
            Section("No le gusta") { TextField("Separado por comas", text: $dislikes) }
            Section("Le encanta") { TextField("Separado por comas", text: $favorites) }
            Section("Manías y texturas") { TextField("«Sin trozos», «la salsa aparte»", text: $quirks) }
            Section("Picante") {
                Picker("Picante", selection: Binding(
                    get: { store.member(member.homeMemberId)?.spice ?? member.spice ?? 0 },
                    set: { v in Task { await store.updateMember(MealMemberUpdate(homeMemberId: member.homeMemberId, spice: v)) } })) {
                    ForEach(MealRules.spiceLevels, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Button("Guardar gustos") {
                    Task { await store.updateMember(MealMemberUpdate(
                        homeMemberId: member.homeMemberId, dislikes: Self.split(dislikes),
                        favorites: Self.split(favorites), quirks: quirks)) }
                }
            }
        }
        .navigationTitle(member.name)
        .onAppear {
            dislikes = member.dislikes.joined(separator: ", ")
            favorites = member.favorites.joined(separator: ", ")
            quirks = member.quirks ?? ""
        }
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Primer paso: las 7 preguntas de arranque, una por pantalla; «Ahora no» en las opcionales.
struct MealStartView: View {
    let store: MealProfileStore
    let profile: MealProfile
    let onClose: () -> Void
    @State private var step = 0
    @State private var outModes: [Int: OutMode] = [:]
    @State private var outModesLoaded = false

    private static let titles = [
        "¿Quién come en casa?", "¿Qué edad tiene cada uno?", "¿Alguna alergia?", "¿Qué dieta sigue cada uno?",
        "¿Qué comidas planificamos?", "¿Qué días coméis fuera?", "¿Cuánto tiempo para cocinar?",
    ]
    private var live: MealProfile { store.profile ?? profile }
    /// B1 es la única obligatoria: no se avanza sin responderla para todos.
    private var canAdvance: Bool {
        switch step {
        case 0: return !live.members.isEmpty
        case 2: return live.members.allSatisfy(\.allergiesAnswered)
        case 4: return live.slots.contains(where: \.enabled)
        default: return true
        }
    }
    private var isOptional: Bool { [1, 3, 5, 6].contains(step) }

    var body: some View {
        VStack(spacing: 0) {
            List { content }
            HStack {
                if isOptional { Button("Ahora no") { advance() } }
                Spacer()
                Button(step == Self.titles.count - 1 ? "Terminar" : "Siguiente") { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            }
            .padding()
        }
        .navigationTitle(Self.titles[step])
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar", action: onClose) } }
    }

    private func advance() {
        if step == 5, outModesLoaded { Task { await store.setOutModes(outModes) } }
        if step == Self.titles.count - 1 { onClose() } else { step += 1 }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            ForEach(store.candidates, id: \.id) { m in
                Toggle(m.name, isOn: Binding(
                    get: { store.member(m.id) != nil }, set: { v in Task { await store.setEats(m, v) } }))
            }
        case 1:
            ForEach(live.members) { m in
                Picker(m.name, selection: Binding(
                    get: { m.ageBand },
                    set: { v in Task { await store.updateMember(MealMemberUpdate(homeMemberId: m.homeMemberId, ageBand: v)) } })) {
                    ForEach(MealRules.ageBands, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
        case 2:
            ForEach(live.members) { m in
                Toggle("\(m.name): sin alergias", isOn: Binding(
                    get: { m.allergiesAnswered && m.allergies.isEmpty },
                    set: { v in if v { Task { await store.updateMember(MealMemberUpdate(
                        homeMemberId: m.homeMemberId, allergiesAnswered: true, allergies: [])) } } }))
                NavigationLink(m.allergies.isEmpty ? "Indicar alergias de \(m.name)" : "Alergias de \(m.name): \(m.allergies.count)") {
                    MealHealthView(store: store, member: m, canEdit: true)
                }
            }
        case 3:
            ForEach(live.members) { m in
                Picker(m.name, selection: Binding(
                    get: { m.diet },
                    set: { v in Task { await store.updateMember(MealMemberUpdate(homeMemberId: m.homeMemberId, diet: v)) } })) {
                    ForEach(MealRules.diets, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
        case 4:
            ForEach(live.slots) { s in
                Toggle(MealRules.label(s.slot, in: MealRules.slots) ?? s.slot, isOn: Binding(
                    get: { s.enabled },
                    set: { v in var c = s; c.enabled = v; Task { await store.setSlots([c]) } }))
            }
        case 5:
            MealOutModes(selected: outModesLoaded ? outModes : MealRules.outModes(live), slots: live.slots, enabled: true) {
                outModes = $0
                outModesLoaded = true
            }
        default:
            Picker("Entre semana", selection: Binding<Int?>(
                get: { live.profile.cookMinutesWeekday },
                set: { v in if let v { Task { await store.updateHome(MealHomeUpdate(cookMinutesWeekday: v)) } } })) {
                Text("Sin definir").tag(Int?.none)
                ForEach(MealRules.cookMinutes, id: \.0) { Text($0.1).tag(Optional($0.0)) }
            }
            Picker("Fin de semana", selection: Binding<Int?>(
                get: { live.profile.cookMinutesWeekend },
                set: { v in if let v { Task { await store.updateHome(MealHomeUpdate(cookMinutesWeekend: v)) } } })) {
                Text("Sin definir").tag(Int?.none)
                ForEach(MealRules.cookMinutes, id: \.0) { Text($0.1).tag(Optional($0.0)) }
            }
        }
    }
}
