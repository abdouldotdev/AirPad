import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

/// Fonctionnalités soumises à l'abonnement.
enum PremiumFeature: String, CaseIterable {
    case keyboard          // clavier et trackpad Mac
    case functionRow       // rangée F1-F12
    case pointerSpeed      // vitesse du curseur
    case multiMac          // plusieurs Macs appairés
    case advancedGestures  // gestes 3 et 4 doigts

    var title: String {
        switch self {
        case .keyboard: return T("Full Mac keyboard & trackpad", "Clavier et trackpad Mac complets")
        case .functionRow: return T("F1–F12 function row", "Rangée de touches F1–F12")
        case .pointerSpeed: return T("Pointer speed control", "Réglage de la vitesse du curseur")
        case .multiMac: return T("Pair multiple Macs", "Appairer plusieurs Macs")
        case .advancedGestures: return T("3 & 4-finger gestures", "Gestes à 3 et 4 doigts")
        }
    }

    var subtitle: String {
        switch self {
        case .keyboard: return T("Type, move, click and scroll from the couch.", "Tapez, déplacez, cliquez et défilez depuis le canapé.")
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

/// Pourquoi la liste des formules est vide. Les trois causes demandent trois
/// réponses différentes : « vérifiez votre connexion » sur une offre absente du
/// store est un mensonge, et il envoie l'utilisateur redémarrer son Wi-Fi pour rien.
enum PlansState: Equatable {
    case idle
    case loading
    /// RevenueCat a répondu et l'offering ne contient aucun produit achetable.
    case unavailable
    /// L'appel lui-même a échoué : réseau, App Store injoignable.
    case failed(String)
    /// Aucune clé RevenueCat : build de développement, l'achat n'existe pas.
    case notConfigured
    case ready

    /// Réessayer n'a de sens que si l'échec peut se résoudre tout seul.
    var isRetryable: Bool {
        switch self {
        case .unavailable, .failed: return true
        case .idle, .loading, .notConfigured, .ready: return false
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let entitlementID = "airpad_pro"

    @Published private(set) var isSubscribed = false
    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?
    @Published private(set) var plansState: PlansState = .idle
    /// Vrai quand le paywall affiche des tarifs simulés : l'écran doit le dire,
    /// sinon une capture d'écran de développement passe pour une vraie offre.
    @Published private(set) var usesStubPlans = false
    /// Détail technique du dernier échec, montré en Debug seulement.
    @Published private(set) var debugError: String?

    var onEvent: ((String, [String: Any]) -> Void)?

    func has(_ feature: PremiumFeature) -> Bool {
        #if DEBUG
        if CaptureMode.forcesSubscription || Self.debugUnlock { return true }
        #endif
        return isSubscribed
    }

    #if DEBUG
    /// Débloque tout sans passer par l'App Store, le temps de filmer la démo.
    /// Persisté : l'app est relancée entre les prises, un booléen en mémoire
    /// obligerait à recocher la case à chaque fois.
    static var debugUnlock: Bool {
        get { UserDefaults.standard.bool(forKey: "debugUnlockPro") }
        set { UserDefaults.standard.set(newValue, forKey: "debugUnlockPro") }
    }
    #endif

    #if canImport(RevenueCat)
    private var offering: Offering?

    func configure(apiKey: String) {
        guard !apiKey.isEmpty else {
            plansState = .notConfigured
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
        Task { await refresh() }
    }

    func refresh() async {
        guard plansState != .notConfigured else { return }
        isLoading = true
        plansState = .loading
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current
            plans = (offering?.availablePackages ?? []).map(Self.plan(from:))
            // Un offering qui répond sans produit achetable n'est pas une panne :
            // c'est le cas quand les produits n'existent pas encore côté App Store
            // Connect, ou que les achats sont restreints sur l'appareil.
            plansState = plans.isEmpty ? .unavailable : .ready
        } catch {
            // RevenueCat lève `configurationError` quand aucun produit du tableau
            // de bord n'a pu être récupéré depuis App Store Connect. Ce n'est pas
            // une panne réseau : le dire envoie l'utilisateur chercher un problème
            // qui n'existe pas chez lui.
            plansState = Self.isStoreConfigurationError(error)
                ? .unavailable
                : .failed(error.localizedDescription)
            // `lastError` déclenche une alerte modale. Un rafraîchissement qui
            // échoue en arrière-plan est déjà raconté par l'état vide ; y ajouter
            // une alerte revient à montrer à l'utilisateur le message de dépannage
            // du SDK, URL internes comprises.
            debugError = error.localizedDescription
        }

        #if DEBUG
        // Sans produits côté App Store Connect, l'offering ne revient jamais :
        // la mise en page du paywall serait impossible à juger. Ces formules
        // calquent les tarifs configurés dans RevenueCat et disparaissent du
        // binaire en Release.
        if plans.isEmpty {
            plans = Self.stubPlans
            usesStubPlans = true
            plansState = .ready
        }
        #endif
    }

    /// Vrai si l'échec vient de la configuration du store, pas du réseau.
    private static func isStoreConfigurationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain.contains("RevenueCat") else { return false }
        return ErrorCode(rawValue: nsError.code) == .configurationError
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

    #if DEBUG
    static let stubPlans: [SubscriptionPlan] = [
        SubscriptionPlan(id: "$rc_annual", title: T("Yearly", "Annuel"), price: "$14.99",
                         period: T("per year", "par an"),
                         trialDescription: T("3-day free trial", "3 jours d'essai gratuit"),
                         isBestValue: true),
        SubscriptionPlan(id: "$rc_weekly", title: T("Weekly", "Hebdomadaire"), price: "$4.99",
                         period: T("per week", "par semaine"),
                         trialDescription: nil, isBestValue: false)
    ]
    #endif

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
    func configure(apiKey: String) { plansState = .notConfigured }
    func refresh() async {}
    func purchase(planID: String) async -> Bool { false }
    func restore() async -> Bool { false }
    func identify(analyticsID: String) {}
    #endif
}
