import Foundation
import UIKit
#if canImport(PostHog)
import PostHog
#endif

/// Couche d'analytique.
///
/// Règle absolue : ni adresse IP locale, ni nom de réseau, ni contenu frappé au
/// clavier ne sortent de l'appareil. Les Macs appairés sont identifiés par un UUID
/// généré localement, les frappes ne sont comptées qu'en volume.
@MainActor
final class Analytics: ObservableObject {
    static let shared = Analytics()

    private(set) var isEnabled = false
    private var pendingPersonProperties: [String: Any] = [:]

    // MARK: - Configuration

    func configure(apiKey: String, host: String) {
        guard !apiKey.isEmpty else { return }
        #if canImport(PostHog)
        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.sessionReplay = false
        PostHogSDK.shared.setup(config)
        isEnabled = true
        bootstrapPersonProperties()
        #endif
    }

    func optOut() {
        #if canImport(PostHog)
        PostHogSDK.shared.optOut()
        #endif
        isEnabled = false
    }

    func optIn() {
        #if canImport(PostHog)
        PostHogSDK.shared.optIn()
        #endif
        isEnabled = true
    }

    /// Identifiant stable, généré sur l'appareil, sans lien avec l'utilisateur réel.
    var distinctID: String {
        if let existing = UserDefaults.standard.string(forKey: "analyticsID") { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: "analyticsID")
        return generated
    }

    // MARK: - Événements

    func capture(_ event: String, _ properties: [String: Any] = [:]) {
        #if canImport(PostHog)
        guard isEnabled else { return }
        PostHogSDK.shared.capture(event, properties: properties)
        #endif
    }

    func screen(_ name: String, _ properties: [String: Any] = [:]) {
        #if canImport(PostHog)
        guard isEnabled else { return }
        PostHogSDK.shared.screen(name, properties: properties)
        #endif
    }

    /// Propriétés rattachées durablement au profil.
    func setPersonProperties(_ properties: [String: Any]) {
        pendingPersonProperties.merge(properties) { _, new in new }
        #if canImport(PostHog)
        guard isEnabled else { return }
        PostHogSDK.shared.identify(distinctID, userProperties: properties)
        #endif
    }

    private func bootstrapPersonProperties() {
        let defaults = UserDefaults.standard
        let sessionCount = defaults.integer(forKey: "sessionCount") + 1
        defaults.set(sessionCount, forKey: "sessionCount")

        var firstSeen = defaults.string(forKey: "firstSeenAt")
        if firstSeen == nil {
            firstSeen = ISO8601DateFormatter().string(from: Date())
            defaults.set(firstSeen, forKey: "firstSeenAt")
        }

        var properties: [String: Any] = [
            "device_model": Self.deviceModel,
            "device_family": UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
            "os_version": UIDevice.current.systemVersion,
            "locale": Locale.current.identifier,
            "language": Locale.current.language.languageCode?.identifier ?? "unknown",
            "country": Locale.current.region?.identifier ?? "unknown",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "session_count": sessionCount,
            "first_seen_at": firstSeen ?? ""
        ]
        properties.merge(pendingPersonProperties) { _, new in new }
        setPersonProperties(properties)
        pendingPersonProperties.removeAll()
    }

    /// Identifiant matériel (« iPhone16,2 ») plutôt que le nom donné par l'utilisateur,
    /// qui contient souvent son prénom.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "unknown" }
        }
    }
}

/// Noms d'événements centralisés : une faute de frappe dans une chaîne libre crée
/// un événement fantôme qu'on ne repère qu'après coup.
enum Event {
    static let onboardingStarted = "onboarding_started"
    static let onboardingStepViewed = "onboarding_step_viewed"
    static let onboardingCompleted = "onboarding_completed"
    static let onboardingSkipped = "onboarding_skipped"

    static let pairingStarted = "pairing_started"
    static let pairingScanSucceeded = "pairing_scan_succeeded"
    static let pairingScanFailed = "pairing_scan_failed"
    static let pairingManualSubmitted = "pairing_manual_submitted"
    static let pairingCameraDenied = "pairing_camera_denied"
    static let firstConnectionSucceeded = "first_connection_succeeded"

    static let connectionEstablished = "connection_established"
    static let connectionLost = "connection_lost"
    static let connectionRejected = "connection_rejected"

    static let trackpadSessionEnded = "trackpad_session_ended"
    static let keysTyped = "keys_typed"
    static let gestureUsed = "gesture_used"
    static let layoutChanged = "layout_changed"
    static let advancedModeToggled = "advanced_mode_toggled"
    static let splitHeightChanged = "split_height_changed"

    static let paywallViewed = "paywall_viewed"
    static let paywallDismissed = "paywall_dismissed"
    static let paywallPlanSelected = "paywall_plan_selected"
    static let purchaseStarted = "purchase_started"
    static let purchaseCompleted = "purchase_completed"
    static let purchaseFailed = "purchase_failed"
    static let purchaseCancelled = "purchase_cancelled"
    static let restoreStarted = "restore_started"
    static let restoreCompleted = "restore_completed"
}
