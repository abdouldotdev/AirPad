import Foundation

/// Localisation minimale : l'app n'a que deux langues et une poignée de chaînes,
/// un catalogue complet serait plus lourd à maintenir que ces appels.
func T(_ en: String, _ fr: String) -> String {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    return lang.hasPrefix("fr") ? fr : en
}
