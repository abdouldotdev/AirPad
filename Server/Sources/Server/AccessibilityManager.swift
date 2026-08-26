import SwiftUI
import ApplicationServices
import AppKit

/// Surveille l'autorisation « Accessibilité » sans laquelle `CGEvent.post` échoue
/// silencieusement : aucune erreur n'est retournée, les événements sont simplement
/// ignorés par le système. C'est la première cause de « l'app ne fait rien ».
@MainActor
final class AccessibilityManager: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    init() {
        // macOS ne notifie pas la révocation ni l'octroi de l'autorisation :
        // le seul moyen fiable de suivre l'état est de l'interroger.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { pollTimer?.invalidate() }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Affiche la fenêtre système de demande d'autorisation.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Ouvre directement le volet Accessibilité des Réglages Système : la fenêtre de
    /// demande n'apparaît qu'une fois par build, l'utilisateur a besoin d'un second chemin.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
