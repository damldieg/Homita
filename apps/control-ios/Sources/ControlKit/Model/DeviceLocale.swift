import Foundation

/// Locale para mostrar fechas y días en el idioma del dispositivo (A6).
/// `Locale.current` puede caer al idioma de desarrollo de la app (en) cuando solo se declara ese
/// idioma; por eso se toma el primer idioma preferido del sistema, con región si la tiene.
public enum DeviceLocale {
    public static var current: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
    }
}
