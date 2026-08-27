import Foundation

#if DEBUG
/// Pilote l'app depuis la ligne de commande pour produire les captures de la fiche
/// App Store toujours dans le même état : `-capture paywall`, `-capture keyboard`…
///
/// Compilé uniquement en Debug : rien de tout ceci n'existe dans le binaire livré.
enum CaptureMode {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-capture"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var isActive: Bool { screen != nil }

    /// Un abonnement simulé permet de photographier les écrans payants sans
    /// dépendre du bac à sable App Store.
    static var forcesSubscription: Bool {
        ["keyboard", "keyboard-azerty", "settings-pro", "trackpad"].contains(screen ?? "")
    }

    /// `-capture onboarding-2` ouvre l'onboarding sur son deuxième écran.
    /// Sans cela les écrans 2 et 3 ne sont atteignables qu'en balayant à la main,
    /// ce qui interdit une capture reproductible.
    static var onboardingStep: Int? {
        guard let screen, screen.hasPrefix("onboarding") else { return nil }
        let parts = screen.split(separator: "-")
        guard parts.count == 2, let page = Int(parts[1]), (1...3).contains(page) else { return nil }
        return page - 1
    }

    static func apply() {
        guard let screen else { return }
        let defaults = UserDefaults.standard

        switch screen {
        case let name where name.hasPrefix("onboarding"):
            defaults.set(false, forKey: "didFinishOnboarding")
            defaults.removeObject(forKey: "pairedMacs")
        case "pairing":
            defaults.set(true, forKey: "didFinishOnboarding")
            defaults.removeObject(forKey: "pairedMacs")
        default:
            defaults.set(true, forKey: "didFinishOnboarding")
            seedPairedMac()
        }

        switch screen {
        case "keyboard":
            defaults.set("QWERTY", forKey: "keyboardLayout")
            defaults.set(true, forKey: "advancedMode")
            defaults.set(0.0, forKey: "trackpadRatio")
        case "keyboard-azerty":
            defaults.set("AZERTY", forKey: "keyboardLayout")
            defaults.set(false, forKey: "advancedMode")
            defaults.set(0.0, forKey: "trackpadRatio")
        case "trackpad":
            defaults.set(0.68, forKey: "trackpadRatio")
        case "free":
            defaults.set(0.62, forKey: "trackpadRatio")
        default:
            break
        }
    }

    private static func seedPairedMac() {
        let mac = PairedMac(name: "MacBook Pro", host: "192.168.1.42", port: 8080, token: "A3F9K2M7")
        guard let data = try? JSONEncoder().encode([mac]) else { return }
        UserDefaults.standard.set(data, forKey: "pairedMacs")
    }
}
#endif
