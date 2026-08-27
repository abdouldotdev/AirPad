import SwiftUI

/// Pré-paywall : l'essai gratuit présenté comme un engagement à zéro euro,
/// avec la suite des événements écrite noir sur blanc.
///
/// Une grille de tarifs demande à l'utilisateur de choisir avant de savoir ce
/// qu'il achète. Cet écran ne pose qu'une question — « voulez-vous essayer,
/// gratuitement ? » — et dit exactement ce qui se passera ensuite. La grille
/// reste accessible d'un geste pour qui veut comparer.
struct TrialIntroView: View {
    let plan: SubscriptionPlan
    var onStart: () -> Void
    var onSeeAllPlans: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            Image("SplashIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ProWordmark(size: 19)
                .padding(.top, 10)

            Text(T("Try it free for 3 days", "Essayez 3 jours, gratuitement"))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.top, 8)

            Text(T("$0.00 today", "0,00 $ aujourd'hui"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .padding(.top, 4)

            timeline
                .padding(.top, 22)

            Spacer(minLength: 12)

            Button(action: onStart) {
                Text(T("Start my free trial", "Démarrer mon essai gratuit"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Brand.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }

            Text(T("3 days free, then \(plan.price) \(plan.period). Cancel anytime.",
                   "3 jours gratuits, puis \(plan.price) \(plan.period). Résiliable à tout moment."))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 10)

            Button(action: onSeeAllPlans) {
                Text(T("See all plans", "Voir toutes les formules"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.top, 14)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 26)
    }

    /// Trois moments, dont celui qui coûte de l'argent. L'annoncer franchement
    /// coûte moins cher qu'un remboursement et qu'un avis à une étoile.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            step(
                icon: "lock.open.fill",
                isFirst: true,
                title: T("Today", "Aujourd'hui"),
                body: T("The full keyboard, F1–F12, pointer speed, gestures and multi-Mac unlock right away. You are charged nothing.",
                        "Le clavier complet, F1–F12, la vitesse du curseur, les gestes et le multi-Mac se débloquent aussitôt. Rien ne vous est facturé.")
            )
            step(
                icon: "creditcard.fill",
                isFirst: false,
                title: T("In 3 days", "Dans 3 jours"),
                body: T("Your trial ends and the subscription starts at \(plan.price) \(plan.period) — unless you cancel before.",
                        "L'essai se termine et l'abonnement démarre à \(plan.price) \(plan.period) — sauf si vous résiliez avant.")
            )
            step(
                icon: "xmark.circle.fill",
                isFirst: false,
                isLast: true,
                title: T("Anytime", "À tout moment"),
                body: T("Cancel in two taps from your Apple Account settings. No email, no form.",
                        "Résiliez en deux gestes depuis les réglages de votre compte Apple. Sans e-mail ni formulaire.")
            )
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func step(icon: String, isFirst: Bool, isLast: Bool = false, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Le trait relie les pastilles : sans lui, trois lignes empilées ne
            // se lisent pas comme une suite dans le temps.
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isFirst ? .white : Brand.accent)
                    .frame(width: 28, height: 28)
                    .background(isFirst ? Brand.accent : Brand.accentWash, in: Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: isLast ? 28 : 62)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer(minLength: 0)
        }
    }
}
