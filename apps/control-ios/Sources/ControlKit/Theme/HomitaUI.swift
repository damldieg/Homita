import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// Capa de componentes de Homita sobre ComponentsKit: todas las pantallas usan estos tipos, no
// los de SwiftUI directamente. En el host macOS (sin ComponentsKit) cada tipo tiene un
// equivalente en SwiftUI para que `swift test` siga compilando.

// MARK: - Tarjeta

/// Tarjeta de Homita: crema claro, borde suave, esquinas muy redondeadas y sombra (como el dashboard).
struct HomitaCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        #if canImport(ComponentsKit)
        // SUCard pone un onTapGesture sobre todo su contenido y se come los toques de filas,
        // enlaces y botones. Se usa solo como fondo, sin gestos: el contenido queda encima.
        content()
            .padding(16)
            .background {
                SUCard(model: cardModel) { Color.clear }
                    .allowsHitTesting(false)
            }
        #else
        content()
            .padding(16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        #endif
    }

    #if canImport(ComponentsKit)
    private var cardModel: CardVM {
        CardVM {
            $0.backgroundColor = uc("#FFFDF9")
            $0.borderColor = uc("#EFE2D0")
            $0.borderWidth = .small
            $0.cornerRadius = .large
            $0.contentPaddings = Paddings(padding: 0)
            $0.shadow = .none
        }
    }
    #endif
}

// MARK: - Encabezado de sección

/// Encabezado de sección estilo dashboard: baldosa con icono, título fuerte y contador en píldora.
struct HomitaSectionHeader: View {
    let title: String
    var count: Int?
    var systemImage: String?
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
            Text(title)
                .font(HomitaFont.geist(19, weight: .bold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(HomitaFont.geist(14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
        .textCase(nil)
        .padding(.vertical, 6)
    }
}

// MARK: - Segmentos

/// Selector de segmentos (Tareas/Listas, Eventos/Rutinas/Calendarios) con `SUSegmentedControl`.
struct HomitaSegmented<ID: Hashable & Sendable>: View {
    @Binding var selection: ID
    let items: [(id: ID, title: String)]

    var body: some View {
        #if canImport(ComponentsKit)
        SUSegmentedControl(selectedId: $selection, model: segmentModel)
        #else
        Picker("", selection: $selection) {
            ForEach(items, id: \.id) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.segmented)
        #endif
    }

    #if canImport(ComponentsKit)
    private var segmentModel: SegmentedControlVM<ID> {
        SegmentedControlVM<ID> { vm in
            vm.isFullWidth = true
            vm.color = ComponentColor(main: uc("#FFFDF9"), contrast: uc("#221D18"))
            vm.items = items.map { item in
                SegmentedControlItemVM(id: item.id) { $0.title = item.title }
            }
        }
    }
    #endif
}

// MARK: - Insignia

/// Insignia de color (estado, rol, contador).
struct HomitaBadge: View {
    let title: String
    /// Color de la paleta en hex (p. ej. el color de un calendario o `Palette.accentHex`).
    var tintHex: String = Palette.accentHex

    var body: some View {
        #if canImport(ComponentsKit)
        SUBadge(model: BadgeVM {
            $0.title = title
            $0.color = ComponentColor(main: uc(tintHex), contrast: uc("#221D18"))
            $0.style = .light
        })
        #else
        Text(title)
            .font(HomitaFont.geist(12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Color(hex: tintHex))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(hex: tintHex).opacity(0.14), in: Capsule())
        #endif
    }
}

// MARK: - Casilla

/// Casilla de completado con `SUCheckbox`.
struct HomitaCheckbox: View {
    let isOn: Bool
    var tintHex: String = Palette.onlineHex
    let onChange: () -> Void

    var body: some View {
        #if canImport(ComponentsKit)
        SUCheckbox(isSelected: Binding(get: { isOn }, set: { _ in onChange() }), model: CheckboxVM {
            $0.color = ComponentColor(main: uc(tintHex), contrast: uc("#FFFFFF"))
        })
        #else
        Button(action: onChange) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isOn ? Color(hex: tintHex) : Palette.inkMuted)
        }
        .buttonStyle(.borderless)
        #endif
    }
}

#if canImport(ComponentsKit)
/// Fondo suave (16 %) del color de la paleta, para insignias.
func ucSoft(_ hex: String) -> UniversalColor {
    .universal(.color(Color(hex: hex).opacity(0.16)))
}
#endif

// MARK: - Cargador

/// Cargador de pantalla completa (`SULoading` sobre velo crema).
struct HomitaLoadingOverlay: View {
    var message: String = "Cargando…"

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 12) {
                #if canImport(ComponentsKit)
                SULoading(model: LoadingVM {
                    $0.color = ComponentColor(main: uc("#C8243B"), contrast: uc("#FFFFFF"))
                })
                #else
                ProgressView().controlSize(.large).tint(Palette.accent)
                #endif
                Text(message)
                    .font(HomitaFont.geist(15, weight: .medium, relativeTo: .callout))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(28)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

// MARK: - Fila y lista

extension View {
    /// Fila de lista como tarjeta: sin fondo ni separador de sistema, con espacio entre tarjetas.
    func homitaRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}


// MARK: - Campo de texto

/// Campo de texto de Homita con `SUInputField` (contraseñas y email incluidos).
struct HomitaField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var isEmail = false
    /// Código (p. ej. invitación): sin autocapitalización ni autocorrección.
    var isCode = false
    @FocusState private var isFocused: Bool

    var body: some View {
        field
            // VoiceOver: el placeholder es el nombre del campo y el texto escrito su valor.
            .accessibilityLabel(placeholder)
            .accessibilityValue(isSecure ? "" : text)
    }

    @ViewBuilder
    private var field: some View {
        #if canImport(ComponentsKit)
        SUInputField(text: $text, isFocused: $isFocused, model: fieldModel)
        #else
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        #endif
    }

    #if canImport(ComponentsKit)
    private var fieldModel: InputFieldVM {
        InputFieldVM {
            $0.placeholder = placeholder
            $0.isSecureInput = isSecure
            $0.isAutocorrectionEnabled = !(isEmail || isSecure || isCode)
            $0.autocapitalization = (isEmail || isCode) ? .never : .sentences
            $0.keyboardType = isEmail ? .emailAddress : .default
            $0.cornerRadius = .large
            $0.style = .bordered
            $0.tintColor = uc("#221D18")
            $0.color = ComponentColor(main: uc("#D9CBB6"), contrast: uc("#221D18"), background: uc("#F7EEE2"))
        }
    }
    #endif
}

// MARK: - Botón secundario

/// Botón de Homita: principal (relleno en acento) o secundario (borde en tinta), sobre `SUButton`.
struct HomitaButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var kind: Kind = .primary
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        #if canImport(ComponentsKit)
        SUButton(model: model, action: action)
            .frame(maxWidth: .infinity)
        #else
        Button(action: action) {
            Text(title)
                .font(HomitaFont.geist(17, weight: .semibold, relativeTo: .body))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isEnabled || isLoading)
        #endif
    }

    #if canImport(ComponentsKit)
    private var model: ButtonVM {
        ButtonVM {
            $0.title = title
            $0.isFullWidth = true
            $0.size = .large
            $0.isEnabled = isEnabled && !isLoading
            $0.isLoading = isLoading
            switch kind {
            case .primary:
                $0.style = .filled
                $0.color = ComponentColor(main: uc(Palette.accentHex), contrast: uc("#FFFFFF"))
            case .secondary:
                $0.style = .bordered(.medium)
                $0.color = ComponentColor(main: uc("#221D18"), contrast: uc("#221D18"))
            }
        }
    }
    #endif
}

// MARK: - Formularios

/// Pantalla de formulario de Homita: fondo crema, barra del mismo color y tarjetas en scroll.
struct HomitaForm<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content()
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .homitaNavigationBar()
    }
}

/// Panel de formulario: tarjeta con encabezado de sección (baldosa, título y contador).
struct HomitaPanel<Content: View>: View {
    let title: String
    var systemImage: String?
    var count: Int?
    var tint: Color = Palette.accent
    let content: () -> Content

    init(_ title: String, systemImage: String? = nil, count: Int? = nil, tint: Color = Palette.accent,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomitaSectionHeader(title: title, count: count, systemImage: systemImage, tint: tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }
}

/// Fila etiquetada dentro de un panel: texto a la izquierda y control a la derecha.
struct HomitaLabeledRow<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Palette.ink)
            Spacer()
            trailing()
        }
    }
}

/// Selector de una opción entre varias con `SURadioGroup` (frecuencia, aviso…).
struct HomitaRadioGroup<ID: Hashable & Sendable>: View {
    @Binding var selection: ID?
    let items: [(id: ID, title: String)]

    var body: some View {
        #if canImport(ComponentsKit)
        SURadioGroup(selectedId: $selection, model: radioModel)
        #else
        Picker("", selection: $selection) {
            ForEach(items, id: \.id) { Text($0.title).tag(Optional($0.id)) }
        }
        .pickerStyle(.inline)
        #endif
    }

    #if canImport(ComponentsKit)
    private var radioModel: RadioGroupVM<ID> {
        RadioGroupVM<ID> { vm in
            vm.color = uc("#C8243B")
            vm.items = items.map { item in
                RadioItemVM(id: item.id) { $0.title = item.title }
            }
        }
    }
    #endif
}

/// Interruptor con el acento de Homita (la librería no trae un switch).
struct HomitaToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Palette.ink)
        }
        .tint(Palette.online)
    }
}

/// Selector de fecha u hora con la tipografía de Homita.
struct HomitaDatePicker: View {
    let title: String
    @Binding var selection: Date
    var components: DatePickerComponents = .date

    var body: some View {
        DatePicker(selection: $selection, displayedComponents: components) {
            Text(title)
                .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Palette.ink)
        }
        .tint(Palette.accent)
    }
}

/// Nota de pie dentro de un panel (texto pequeño en tinta suave).
struct HomitaFootnote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(HomitaFont.geist(13, relativeTo: .footnote))
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Mensaje de error dentro de un formulario.
struct HomitaErrorText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(HomitaFont.geist(14, weight: .medium, relativeTo: .footnote))
            .foregroundStyle(Palette.accent)
    }
}

extension View {
    /// Confirmación de una acción destructiva: `SUAlert` con «Cancelar» y el botón de confirmar.
    func homitaConfirm(_ title: String, isPresented: Binding<Bool>, confirmTitle: String, onConfirm: @escaping () -> Void) -> some View {
        #if canImport(ComponentsKit)
        return self.suAlert(
            isPresented: isPresented,
            model: AlertVM {
                $0.title = title
                $0.primaryButton = AlertButtonVM {
                    $0.title = confirmTitle
                    $0.color = ComponentColor(main: uc("#C8243B"), contrast: uc("#FFFFFF"))
                }
                $0.secondaryButton = AlertButtonVM { $0.title = "Cancelar" }
            },
            primaryAction: onConfirm
        )
        #else
        return self.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(confirmTitle, role: .destructive, action: onConfirm)
            Button("Cancelar", role: .cancel) {}
        }
        #endif
    }
}

/// Botón pequeño para acciones dentro de una fila (Hacer admin, Quitar, Revocar…), sobre `SUButton`.
struct HomitaChipButton: View {
    enum Kind { case neutral, destructive }

    let title: String
    var kind: Kind = .neutral
    let action: () -> Void

    var body: some View {
        #if canImport(ComponentsKit)
        SUButton(model: ButtonVM {
            $0.title = title
            $0.size = .small
            $0.style = .bordered(.small)
            $0.color = ComponentColor(main: uc(kind == .destructive ? Palette.accentHex : "#221D18"), contrast: uc(kind == .destructive ? Palette.accentHex : "#221D18"))
        }, action: action)
        .fixedSize()
        #else
        Button(title, role: kind == .destructive ? .destructive : nil, action: action)
            .buttonStyle(.bordered)
        #endif
    }
}

/// Fila de lista como tarjeta con acción a la derecha (enlace de administración, miembro…).
struct HomitaLinkRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var tint: String = Palette.accentHex

    var body: some View {
        HomitaCard {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: tint))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(HomitaFont.geist(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }
}

/// Estado vacío de Homita: icono en baldosa, título, explicación y botón para crear desde ahí.
struct HomitaEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HomitaCard {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 84, height: 84)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 26))
                    .accessibilityHidden(true)
                Text(title)
                    .font(HomitaFont.geist(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(HomitaFont.geist(15, relativeTo: .body))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                HomitaButton(title: actionTitle, action: action)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
    }
}
