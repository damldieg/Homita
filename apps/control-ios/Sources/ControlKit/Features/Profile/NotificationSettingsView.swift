import SwiftUI
import HomitaShared
#if os(iOS)
import UIKit
#endif

/// Ajustes › Notificaciones: todo lo que la app hace fuera de sí misma (avisos, widgets, pantalla de
/// bloqueo) se puede apagar aquí. Cada toggle guarda al instante y reaplica con los últimos datos.
struct NotificationSettingsView: View {
    @State private var preferences = NotificationPreferencesStore().load()
    @State private var permission: NotificationPermission = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    private let scheduler = NotificationScheduler()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if permission == .denied { permissionCard }
                remindersCard
                lockScreenCard
                widgetsCard
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Notificaciones")
        .homitaNavigationBar()
        .task { permission = await scheduler.permission() }
        // Al volver de los Ajustes de iOS se relee el permiso.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { permission = await scheduler.permission() } }
        }
        .onAppear { DeepLinkCenter.shared.consume(.ajustesNotificaciones) }
    }

    // MARK: - Tarjetas

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(title: "Permiso desactivado", systemImage: "bell.slash", tint: Palette.err)
            HomitaFootnote(text: "iOS tiene bloqueadas las notificaciones de Homita. Actívalas en los Ajustes del iPhone para recibir avisos.")
            HomitaButton(title: "Abrir Ajustes de iOS", kind: .secondary) { openSystemSettings() }
                .accessibilityIdentifier("notificaciones.abrir-ajustes-ios")
        }
        .modifier(CardStyle())
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomitaSectionHeader(title: "Avisos", systemImage: "bell")
            HomitaToggle(title: "Eventos", isOn: binding(\.eventReminders))
                .accessibilityIdentifier("notificaciones.eventos")
            HomitaToggle(title: "Rutinas", isOn: binding(\.routineReminders))
                .accessibilityIdentifier("notificaciones.rutinas")
            HomitaToggle(title: "Resumen de tareas pendientes", isOn: binding(\.taskDigest))
                .accessibilityIdentifier("notificaciones.resumen-tareas")
            if preferences.taskDigest {
                HomitaDatePicker(title: "Hora del resumen", selection: digestTime, components: .hourAndMinute)
                    .accessibilityIdentifier("notificaciones.hora-resumen")
            }
            HomitaFootnote(text: "Los avisos de eventos y rutinas usan la alarma de cada uno («Sin aviso» no notifica).")
        }
        .modifier(CardStyle())
    }

    private var lockScreenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomitaSectionHeader(title: "Pantalla de bloqueo", systemImage: "lock.iphone")
            HomitaToggle(title: "Rutinas en tiempo real", isOn: binding(\.routineLiveActivity))
                .accessibilityIdentifier("notificaciones.live-activity")
            HomitaFootnote(text: "Muestra la rutina en curso o la próxima (a menos de una hora) con cuenta atrás, como un viaje en curso. Solo sale para las rutinas a las que está asignada tu persona, con tu cuenta iniciada. Se inicia al abrir Homita; también puedes quitarla desde Ajustes de iOS › Homita › Actividades en directo.")
        }
        .modifier(CardStyle())
    }

    private var widgetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomitaSectionHeader(title: "Widgets", systemImage: "square.grid.2x2")
            HomitaToggle(title: "Datos en widgets", isOn: binding(\.widgets))
                .accessibilityIdentifier("notificaciones.widgets")
            HomitaFootnote(text: "Añade «Rutinas de hoy», «Accesos rápidos» o los widgets «Nueva tarea», «Nuevo evento» y «Nueva rutina» desde la pantalla de inicio o de bloqueo. Con el toggle apagado muestran un aviso y Homita no les deja datos.")
        }
        .modifier(CardStyle())
    }

    // MARK: - Bindings

    /// Binding de un toggle: guarda y reaplica (avisos, widgets, Live Activity) al cambiar.
    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { newValue in
                preferences[keyPath: keyPath] = newValue
                commit()
            }
        )
    }

    private var digestTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: preferences.taskDigestHour, minute: preferences.taskDigestMinute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.taskDigestHour = parts.hour ?? 9
                preferences.taskDigestMinute = parts.minute ?? 0
                commit()
            }
        )
    }

    private func commit() {
        let value = preferences
        Task { @MainActor in
            HomitaSync.shared.preferences = value
            await HomitaSync.shared.preferencesChanged()
            permission = await scheduler.permission()
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}

/// Fondo de tarjeta de Ajustes.
private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }
}
