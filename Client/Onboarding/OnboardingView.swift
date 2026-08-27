import SwiftUI

struct OnboardingStep: Identifiable {
    let id: Int
    let eyebrow: String
    let title: String
    let body: String
    let illustration: AnyView
}

/// Trois écrans : le problème, la solution, l'appairage.
///
/// Trois, parce que le parcours a exactement trois choses à faire comprendre, et
/// qu'un utilisateur qui vient d'installer un utilitaire abandonne au-delà.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    private var steps: [OnboardingStep] {
        [
            OnboardingStep(
                id: 0,
                eyebrow: T("THE PROBLEM", "LE PROBLÈME"),
                title: T("Your Mac is across the room", "Votre Mac est à l'autre bout de la pièce"),
                body: T("Film on the TV, presentation on the projector, recipe on the kitchen screen — and every pause means standing up.",
                        "Un film sur la TV, une présentation au vidéoprojecteur, une recette sur l'écran de la cuisine — et chaque pause vous fait lever."),
                illustration: AnyView(DistanceIllustration())
            ),
            OnboardingStep(
                id: 1,
                eyebrow: T("THE FIX", "LA SOLUTION"),
                title: T("Your iPhone is the trackpad", "Votre iPhone devient le trackpad"),
                body: T("Move, click, scroll — straight from your couch, over your own Wi-Fi. Nothing leaves your network.",
                        "Déplacez, cliquez, faites défiler — depuis le canapé, sur votre propre Wi-Fi. Rien ne sort de votre réseau."),
                illustration: AnyView(ControlIllustration())
            ),
            OnboardingStep(
                id: 2,
                eyebrow: T("AND THE KEYBOARD", "ET LE CLAVIER"),
                title: T("Type without getting up", "Tapez sans vous lever"),
                body: T("A full keyboard with ⇧ ⌘ ⌥ ⌃ and the F1–F12 row, right under your thumbs. Search, rename, reply — without leaving the couch.",
                        "Un clavier complet avec ⇧ ⌘ ⌥ ⌃ et la rangée F1–F12, sous vos pouces. Chercher, renommer, répondre — sans quitter le canapé."),
                illustration: AnyView(KeyboardIllustration())
            ),
            OnboardingStep(
                id: 3,
                eyebrow: T("ONE STEP LEFT", "DERNIÈRE ÉTAPE"),
                title: T("Scan the code on your Mac", "Scannez le code sur votre Mac"),
                body: T("Install the free AirPad companion on your Mac, then scan the pairing code it shows. It takes about a minute.",
                        "Installez l'application AirPad gratuite sur votre Mac, puis scannez le code d'appairage affiché. Il faut environ une minute."),
                illustration: AnyView(PairingIllustration())
            )
        ]
    }

    var body: some View {
        ZStack {
            // Le halo suit l'étape : le fond raconte la progression sans texte.
            RadialGradient(
                colors: [accentColor.opacity(0.32), Color(white: 0.07)],
                center: .top, startRadius: 20, endRadius: 520
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: index)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if index < steps.count - 1 {
                        Button(T("Skip", "Passer")) {
                            Analytics.shared.capture(Event.onboardingSkipped, ["step": index])
                            onFinish()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 44)

                TabView(selection: $index) {
                    ForEach(steps) { step in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            step.illustration
                                .frame(maxHeight: 240)
                                .frame(maxWidth: .infinity)
                            Spacer(minLength: 0)

                            VStack(spacing: 12) {
                                Text(step.eyebrow)
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(1.6)
                                    .foregroundStyle(accentColor)

                                Text(step.title)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white)

                                Text(step.body)
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .padding(.horizontal, 12)
                            }
                            .padding(.horizontal, 28)
                            Spacer(minLength: 20)
                        }
                        .tag(step.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: 560)

                VStack(spacing: 20) {
                    HStack(spacing: 7) {
                        ForEach(steps) { step in
                            Capsule()
                                .fill(step.id == index ? accentColor : Color.white.opacity(0.22))
                                .frame(width: step.id == index ? 22 : 7, height: 7)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
                        }
                    }

                    Button {
                        advance()
                    } label: {
                        Text(index == steps.count - 1 ? T("Pair my Mac", "Appairer mon Mac") : T("Continue", "Continuer"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
            }
        }
        .onAppear {
            #if DEBUG
            if let step = CaptureMode.onboardingStep { index = step }
            #endif
            Analytics.shared.capture(Event.onboardingStarted)
            Analytics.shared.capture(Event.onboardingStepViewed, ["step": 0])
        }
        .onChange(of: index) { newValue in
            Analytics.shared.capture(Event.onboardingStepViewed, ["step": newValue])
        }
    }

    private var accentColor: Color { OnboardingPalette.accent(for: index) }

    private func advance() {
        if index < steps.count - 1 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index += 1 }
        } else {
            Analytics.shared.capture(Event.onboardingCompleted)
            onFinish()
        }
    }
}
