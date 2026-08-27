import SwiftUI

struct PaywallView: View {
    @ObservedObject var subscriptions: SubscriptionManager
    /// Fonctionnalité qui a déclenché l'affichage : sert à mettre en avant le bon
    /// argument et à mesurer quelle porte convertit le mieux.
    var trigger: PremiumFeature?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String?
    @State private var isWorking = false
    /// Le pré-paywall passe la main à la grille dès que l'utilisateur veut comparer.
    @State private var showsAllPlans = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.1), Color(red: 0.06, green: 0.09, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let trialPlan, !showsAllPlans {
                VStack(spacing: 0) {
                    TrialIntroView(
                        plan: trialPlan,
                        onStart: {
                            selectedPlanID = trialPlan.id
                            Analytics.shared.capture(Event.paywallPlanSelected, ["plan": trialPlan.id])
                            Task { await purchase() }
                        },
                        onSeeAllPlans: { showsAllPlans = true }
                    )
                    footer
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 26) {
                        header
                        featureList
                        planPicker
                        purchaseButton
                        footer
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                }
            }

            if subscriptions.isLoading || isWorking {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView().tint(.white).scaleEffect(1.3)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Analytics.shared.capture(Event.paywallDismissed, ["trigger": trigger?.rawValue ?? "settings"])
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(10)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .padding(16)
        }
        .task {
            await subscriptions.refresh()
            if selectedPlanID == nil {
                // L'annuel est présélectionné : c'est le plan avec l'essai gratuit.
                selectedPlanID = subscriptions.plans.first(where: { $0.isBestValue })?.id ?? subscriptions.plans.first?.id
            }
        }
        .onAppear {
            Analytics.shared.capture(Event.paywallViewed, ["trigger": trigger?.rawValue ?? "settings"])
        }
        .alert(T("Something went wrong", "Une erreur est survenue"),
               isPresented: .constant(subscriptions.lastError != nil)) {
            Button("OK") { subscriptions.lastError = nil }
        } message: {
            Text(subscriptions.lastError ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("SplashIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            ProWordmark(size: 30)

            Text(trigger?.subtitle ?? T("Everything your Mac keyboard and trackpad can do, on your phone.",
                                        "Tout ce que font le clavier et le trackpad de votre Mac, sur votre téléphone."))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 24)
    }

    private var featureList: some View {
        VStack(spacing: 14) {
            ForEach(PremiumFeature.allCases, id: \.rawValue) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(feature == trigger ? Color.blue : .white.opacity(0.85))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(feature.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var planPicker: some View {
        if subscriptions.plans.isEmpty {
            VStack(spacing: 14) {
                Text(unavailableMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))

                // « Réessayez » sans bouton laisse l'utilisateur dans une impasse :
                // rouvrir le paywall est la seule issue, et rien ne le dit.
                if subscriptions.plansState.isRetryable {
                    Button(T("Try again", "Réessayer")) {
                        Task { await subscriptions.refresh() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                }

            }
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 12) {
                #if DEBUG
                if subscriptions.usesStubPlans {
                    Text("DEBUG — tarifs simulés : les produits n'existent pas encore dans App Store Connect")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.orange.opacity(0.9))
                }
                #endif
                ForEach(subscriptions.plans) { plan in
                    PlanRow(plan: plan, isSelected: plan.id == selectedPlanID)
                        .onTapGesture {
                            selectedPlanID = plan.id
                            Analytics.shared.capture(Event.paywallPlanSelected, ["plan": plan.id])
                        }
                }
            }
        }
    }

    private var unavailableMessage: String {
        switch subscriptions.plansState {
        case .failed:
            return T("We couldn't reach the App Store. Check your connection and try again.",
                     "Impossible de joindre l'App Store. Vérifiez votre connexion et réessayez.")
        case .notConfigured:
            return T("In-app purchases aren't available in this build.",
                     "Les achats intégrés ne sont pas disponibles dans cette version.")
        default:
            return T("No subscription is available for this account right now. This can happen if purchases are restricted on the device.",
                     "Aucun abonnement n'est disponible pour ce compte pour le moment. Cela arrive si les achats sont restreints sur l'appareil.")
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await purchase() }
            } label: {
                Text(selectedPlan?.trialDescription != nil
                     ? T("Start free trial", "Démarrer l'essai gratuit")
                     : T("Continue", "Continuer"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Brand.accent,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(.white)
            }
            .disabled(selectedPlanID == nil)
            .opacity(selectedPlanID == nil ? 0.5 : 1)

            // Apple exige que le renouvellement automatique soit annoncé sur l'écran d'achat.
            Text(T("Renews automatically. Cancel anytime in Settings.",
                   "Renouvellement automatique. Annulable à tout moment dans les Réglages."))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Button(T("Restore", "Restaurer")) {
                Task {
                    isWorking = true
                    let restored = await subscriptions.restore()
                    isWorking = false
                    if restored { dismiss() }
                }
            }
            Link(T("Terms", "CGU"), destination: LegalLinks.terms)
            Link(T("Privacy", "Confidentialité"), destination: LegalLinks.privacy)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.55))
        .padding(.bottom, 12)
    }

    /// L'essai gratuit n'existe que sur l'annuel : sans lui, pas de pré-paywall,
    /// on va droit à la grille plutôt que de promettre un essai inexistant.
    private var trialPlan: SubscriptionPlan? {
        subscriptions.plans.first(where: { $0.trialDescription != nil })
    }

    private var selectedPlan: SubscriptionPlan? {
        subscriptions.plans.first(where: { $0.id == selectedPlanID })
    }

    private func purchase() async {
        guard let planID = selectedPlanID else { return }
        isWorking = true
        let success = await subscriptions.purchase(planID: planID)
        isWorking = false
        if success { dismiss() }
    }
}

struct PlanRow: View {
    let plan: SubscriptionPlan
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.3))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if plan.isBestValue {
                        Text(T("BEST VALUE", "MEILLEURE OFFRE"))
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.green, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                if let trial = plan.trialDescription {
                    Text(trial)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(plan.price)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(plan.period)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

enum LegalLinks {
    static let privacy = URL(string: "https://abdouldotdev.github.io/AirPad/privacy.html")!
    static let terms = URL(string: "https://abdouldotdev.github.io/AirPad/terms.html")!
    static let macDownload = URL(string: "https://github.com/abdouldotdev/AirPad/releases/latest")!
}
