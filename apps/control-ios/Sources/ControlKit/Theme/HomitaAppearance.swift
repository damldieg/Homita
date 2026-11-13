import SwiftUI
#if canImport(UIKit)
import UIKit

/// Barra superior y de pestañas con la paleta Homita y Inter en los títulos (E0-01).
/// SwiftUI no expone todo esto: se configura una vez al arrancar, vía UIKit.
enum HomitaAppearance {
    static func apply() {
        let ink = UIColor(Palette.ink)
        let title = UIFont(name: "Inter-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let largeTitle = UIFont(name: "Inter-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Palette.background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.font: title, .foregroundColor: ink]
        nav.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: ink]
        // Borde de desplazamiento transparente (título grande sobre el crema); opaca al desplazar.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = [.font: title, .foregroundColor: ink]
        edge.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Palette.rail)
        tab.shadowColor = UIColor(Palette.line)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Encabezados de sección de List/Form: Inter semibold en tinta suave, como SectionLabel del dashboard.
        let sectionFont = UIFont(name: "Inter-SemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
        UILabel.appearance(whenContainedInInstancesOf: [UITableViewHeaderFooterView.self]).font = sectionFont
        UILabel.appearance(whenContainedInInstancesOf: [UITableViewHeaderFooterView.self]).textColor = UIColor(Palette.inkSoft)

        // Segmentos (Picker .segmented): fondo de la pista y seleccionado en tarjeta.
        UISegmentedControl.appearance().backgroundColor = UIColor(Palette.rail)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Palette.card)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: ink], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: ink], for: .selected)
    }
}
#else
enum HomitaAppearance {
    static func apply() {}
}
#endif
