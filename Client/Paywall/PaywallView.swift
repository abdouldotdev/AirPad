import SwiftUI

struct PaywallView: View {
    @ObservedObject var subscriptions: SubscriptionManager
    /// Fonctionnalité qui a déclenché l'affichage : sert à mettre en avant le bon
    /// argument et à mesurer quelle porte convertit le mieux.
    var trigger: PremiumFeature?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.1), Color(red: 0.06, green: 0.09, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

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
            Image(systemName: trigger?.systemImage ?? "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

            Text(T("AirPad Pro", "AirPad Pro"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

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
            Text(T("Plans are unavailable right now. Check your connection and try again.",
                   "Les offres sont indisponibles pour le moment. Vérifiez votre connexion et réessayez."))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.vertical, 18)
        } else {
            VStack(spacing: 12) {
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
                        LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing),
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
    static let privacy = URL(string: "https://abdouldotdev.github.io/MacTrack/privacy.html")!
    static let terms = URL(string: "https://abdouldotdev.github.io/MacTrack/terms.html")!
    static let macDownload = URL(string: "https://github.com/abdouldotdev/MacTrack/releases/latest")!
}
