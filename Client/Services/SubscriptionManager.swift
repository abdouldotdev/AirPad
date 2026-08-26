import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

/// Fonctionnalités soumises à l'abonnement.
enum PremiumFeature: String, CaseIterable {
    case keyboard          // clavier Mac complet
    case functionRow       // rangée F1-F12
    case pointerSpeed      // vitesse du curseur
    case multiMac          // plusieurs Macs appairés
    case advancedGestures  // gestes 3 et 4 doigts

    var title: String {
        switch self {
        case .keyboard: return T("Full Mac keyboard", "Clavier Mac complet")
        case .functionRow: return T("F1–F12 function row", "Rangée de touches F1–F12")
        case .pointerSpeed: return T("Pointer speed control", "Réglage de la vitesse du curseur")
        case .multiMac: return T("Pair multiple Macs", "Appairer plusieurs Macs")
        case .advancedGestures: return T("3 & 4-finger gestures", "Gestes à 3 et 4 doigts")
        }
    }

    var subtitle: String {
        switch self {
        case .keyboard: return T("Type on your Mac from anywhere in the room.", "Tapez sur votre Mac depuis n'importe où dans la pièce.")
        case .functionRow: return T("Volume, brightness, Mission Control.", "Volume, luminosité, Mission Control.")
        case .pointerSpeed: return T("Tune tracking from precise to fast.", "Du pointage précis au déplacement rapide.")
        case .multiMac: return T("Switch between your desktop and laptop.", "Basculez entre votre fixe et votre portable.")
        case .advancedGestures: return T("Swipe between desktops and apps.", "Naviguez entre bureaux et applications.")
        }
    }

    var systemImage: String {
        switch self {
        case .keyboard: return "keyboard"
        case .functionRow: return "slider.horizontal.3"
        case .pointerSpeed: return "speedometer"
        case .multiMac: return "macbook.and.iphone"
        case .advancedGestures: return "hand.draw"
        }
    }
}

struct SubscriptionPlan: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let period: String
    let trialDescription: String?
    let isBestValue: Bool
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let entitlementID = "premium"

    @Published private(set) var isSubscribed = false
    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    var onEvent: ((String, [String: Any]) -> Void)?

    func has(_ feature: PremiumFeature) -> Bool {
        #if DEBUG
        if CaptureMode.forcesSubscription { return true }
        #endif
        return isSubscribed
    }

    #if canImport(RevenueCat)
    private var offering: Offering?

    func configure(apiKey: String) {
        guard !apiKey.isEmpty else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current
            plans = (offering?.availablePackages ?? []).map(Self.plan(from:))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(planID: String) async -> Bool {
        guard let package = offering?.availablePackages.first(where: { $0.identifier == planID }) else { return false }
        isLoading = true
        defer { isLoading = false }
        onEvent?("purchase_started", ["plan": planID])
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                onEvent?("purchase_cancelled", ["plan": planID])
                return false
            }
            apply(result.customerInfo)
            onEvent?("purchase_completed", ["plan": planID, "is_subscribed": isSubscribed])
            return isSubscribed
        } catch {
            lastError = error.localizedDescription
            onEvent?("purchase_failed", ["plan": planID, "error": error.localizedDescription])
            return false
        }
    }

    func restore() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        onEvent?("restore_started", [:])
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            onEvent?("restore_completed", ["is_subscribed": isSubscribed])
            return isSubscribed
        } catch {
            lastError = error.localizedDescription
            onEvent?("restore_failed", ["error": error.localizedDescription])
            return false
        }
    }

    func identify(analyticsID: String) {
        Task { try? await Purchases.shared.logIn(analyticsID) }
    }

    private func apply(_ info: CustomerInfo) {
        isSubscribed = info.entitlements[Self.entitlementID]?.isActive == true
    }

    private static func plan(from package: Package) -> SubscriptionPlan {
        let product = package.storeProduct
        let isAnnual = package.packageType == .annual
        var trial: String?
        if let discount = product.introductoryDiscount, discount.paymentMode == .freeTrial {
            let unit = discount.subscriptionPeriod.value
            trial = T("\(unit)-day free trial", "\(unit) jours d'essai gratuit")
        }
        return SubscriptionPlan(
            id: package.identifier,
            title: isAnnual ? T("Yearly", "Annuel") : T("Weekly", "Hebdomadaire"),
            price: product.localizedPriceString,
            period: isAnnual ? T("per year", "par an") : T("per week", "par semaine"),
            trialDescription: trial,
            isBestValue: isAnnual
        )
    }
    #else
    // Le SDK n'est pas encore lié : l'app reste compilable et testable en gratuit.
    func configure(apiKey: String) {}
    func refresh() async {}
    func purchase(planID: String) async -> Bool { false }
    func restore() async -> Bool { false }
    func identify(analyticsID: String) {}
    #endif
}
