import SwiftUI

struct AirPadView: View {
    @ObservedObject var client: NetworkClient
    @ObservedObject var macStore: PairedMacStore
    @ObservedObject var subscriptions: SubscriptionManager

    @AppStorage("advancedMode") private var advancedMode = false
    @AppStorage("keyboardLayout") private var keyboardLayoutRaw = KeyboardLayout.qwerty.rawValue
    @AppStorage("trackingSpeed") private var trackingSpeed: Double = 1.0
    @AppStorage("trackpadRatio") private var trackpadRatio: Double = 0.0

    @StateObject private var modifiers = ModifierState()
    @State private var dragOffset: CGFloat = 0
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var paywallTrigger: PremiumFeature?
    @State private var isBlinking = false
    @State private var trackpadSessionStart: Date?
    @State private var typedKeyCount = 0

    private var layout: KeyboardLayout {
        KeyboardLayout(rawValue: keyboardLayoutRaw) ?? .qwerty
    }

    /// L'accès aux fonctions passe par un abonnement actif — l'essai gratuit
    /// en est un : RevenueCat garde l'entitlement actif pendant toute sa durée.
    private var hasPro: Bool { subscriptions.has(.keyboard) }
    private var hasKeyboard: Bool { hasPro }

    var body: some View {
        ZStack {
            Color(white: 0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                GeometryReader { geo in
                    splitLayout(in: geo)
                }
            }
        }
        .onAppear {
            // En gratuit, le trackpad est la fonctionnalité utilisable : il doit être
            // déployé d'entrée, sinon l'app s'ouvre sur un clavier verrouillé.
            if !hasKeyboard && trackpadRatio < 0.2 { trackpadRatio = 0.62 }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isBlinking = true }
            Analytics.shared.screen("remote")
        }
        .onChange(of: subscriptions.isSubscribed) { isSubscribed in
            if !isSubscribed {
                macStore.trimToFreeTier()
                modifiers.reset()
            }
            Analytics.shared.setPersonProperties(["subscription_status": isSubscribed ? "active" : "free"])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client, macStore: macStore, subscriptions: subscriptions)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptions: subscriptions, trigger: paywallTrigger)
        }
    }

    // MARK: - Barre supérieure

    private var topBar: some View {
        HStack {
            Image(systemName: "gearshape.fill").padding(12).opacity(0)
            Spacer()
            connectionPill
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(12)
                    .background(Color.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var connectionPill: some View {
        Button {
            if !client.isConnected { showSettings = true }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .opacity(client.isConnected ? 1.0 : (isBlinking ? 0.2 : 1.0))
                Text(statusLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4), in: Capsule())
        }
        .accessibilityLabel(statusLabel)
    }

    private var statusColor: Color {
        switch client.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .rejected: return .red
        default: return .red
        }
    }

    private var statusLabel: String {
        switch client.state {
        case .connected: return T("Connected", "Connecté")
        case .connecting: return T("Connecting…", "Connexion…")
        case .reconnecting: return T("Reconnecting…", "Reconnexion…")
        // Un refus est sans issue tant qu'on ne dit pas laquelle : le jeton
        // stocké est périmé, et seul un ré-appairage le remplace. La pastille
        // ouvre déjà les réglages — encore fallait-il l'annoncer.
        case .rejected: return T("Pairing rejected — tap to re-pair", "Appairage refusé — toucher pour ré-appairer")
        default: return T("Not connected", "Non connecté")
        }
    }

    // MARK: - Partage clavier / trackpad

    private func splitLayout(in geo: GeometryProxy) -> some View {
        let currentRatio = trackpadRatio - (dragOffset / max(geo.size.height, 1))
        let clamped = min(max(currentRatio, 0.0), 1.0)
        let trackpadHeight = max(0, geo.size.height * clamped)
        let keyboardHeight = max(0, geo.size.height * (1.0 - clamped) - 40)

        return VStack(spacing: 0) {
            keyboardZone
                .frame(height: keyboardHeight)
                .clipped()
                .opacity(keyboardHeight > 50 ? 1 : 0)

            dockHandle(in: geo)

            if trackpadHeight > 0 {
                trackpadZone(height: trackpadHeight)
                    .frame(height: trackpadHeight)
                    .clipped()
                    .opacity(trackpadHeight > 20 ? 1 : 0)
                    .blur(radius: hasPro ? 0 : 7)
                    .disabled(!hasPro)
                    .allowsHitTesting(hasPro)
            }
        }
        // L'abonnement commande toute la surface de contrôle, trackpad compris.
        // Un seul verrou pour les deux zones : deux capsules superposées se
        // liraient comme deux offres distinctes.
        .overlay { if !hasPro { keyboardLock } }
    }

    private func dockHandle(in geo: GeometryProxy) -> some View {
        ZStack {
            Color(white: 0.1)
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 130, height: 5)
                .padding(.vertical, 16)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                trackpadRatio = trackpadRatio > 0.1 ? 0.0 : 0.5
            }
            reportSplit()
        }
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    var newRatio = trackpadRatio - (value.translation.height / max(geo.size.height, 1))
                    if newRatio < 0.15 { newRatio = 0.0 }
                    trackpadRatio = min(max(newRatio, 0.0), 1.0)
                    dragOffset = 0
                    reportSplit()
                }
        )
        .accessibilityLabel(T("Resize trackpad", "Redimensionner le trackpad"))
    }

    private func reportSplit() {
        Analytics.shared.capture(Event.splitHeightChanged, ["ratio": Int(trackpadRatio * 100)])
    }

    // MARK: - Trackpad

    private func trackpadZone(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            TrackpadUIKitView(
                client: client,
                trackingSpeed: subscriptions.has(.pointerSpeed) ? trackingSpeed : 1.0,
                allowsAdvancedGestures: subscriptions.has(.advancedGestures),
                onGesture: { name in
                    Analytics.shared.capture(Event.gestureUsed, ["gesture": name])
                },
                onPremiumGesture: {
                    present(.advancedGestures)
                }
            )
            .frame(maxHeight: .infinity)
            .onAppear { trackpadSessionStart = Date() }
            .onDisappear {
                guard let start = trackpadSessionStart else { return }
                Analytics.shared.capture(Event.trackpadSessionEnded,
                                         ["duration_s": Int(Date().timeIntervalSince(start))])
                trackpadSessionStart = nil
            }

            if height > 200 {
                Divider().background(Color.black.opacity(0.1))
                HStack(spacing: 0) {
                    clickButton(title: T("Left Click", "Clic gauche"), style: .light) { client.sendClick() }
                    Divider().background(Color.black.opacity(0.1))
                    clickButton(title: T("Right Click", "Clic droit"), style: .medium) { client.sendRightClick() }
                }
                .frame(height: 60)
            }
        }
        .background(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
        .padding(16)
    }

    private func clickButton(title: String, style: UIImpactFeedbackGenerator.FeedbackStyle, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.footnote.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Clavier

    private var keyboardZone: some View {
        ZStack {
            keyboardRows
                .blur(radius: hasKeyboard ? 0 : 7)
                .disabled(!hasKeyboard)
                .allowsHitTesting(hasKeyboard)

        }
    }

    private var keyboardRows: some View {
        GeometryReader { geo in
            // Sur iPad, un clavier étiré sur toute la largeur donne des touches
            // démesurées et injouables au pouce : la largeur est bornée et centrée.
            let width = min(geo.size.width - 16, 620)
            let baseKeyWidth = max(0, (width - (9 * 6)) / 10)
            let rowCount = CGFloat(advancedMode && subscriptions.has(.functionRow) ? 6 : 5)
            // Les touches s'étirent pour occuper la hauteur libre quand le trackpad
            // est replié, sans jamais dépasser une fois et demie leur largeur :
            // au-delà, elles cessent de ressembler à un clavier.
            let fitted = (geo.size.height - 24 - (rowCount * 8)) / rowCount
            let rowHeight = max(baseKeyWidth * 0.75, min(fitted, baseKeyWidth * 1.5))

            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    if advancedMode && subscriptions.has(.functionRow) {
                        KeyboardRow(keys: KeyboardLayouts.functionRow, client: client, modifiers: modifiers)
                            .frame(height: rowHeight * 0.8)
                    }
                    row(KeyboardLayouts.numberRow, height: rowHeight)
                    row(KeyboardLayouts.topRow(layout), height: rowHeight)
                    row(KeyboardLayouts.homeRow(layout), height: rowHeight)
                    row(KeyboardLayouts.bottomRow(layout), height: rowHeight)
                    row(KeyboardLayouts.modifierRow, height: rowHeight)
                }
                .padding(8)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                .frame(width: width)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
    }

    private func row(_ keys: [MacKey], height: CGFloat) -> some View {
        KeyboardRow(keys: keys, client: client, modifiers: modifiers)
            .frame(height: height)
            .onAppear { }
    }

    /// Ce qui recouvre le clavier verrouillé.
    ///
    /// Un panneau qui dit « c'est payant » ferme la porte ; celui-ci l'ouvre en
    /// annonçant d'abord ce que ça coûte aujourd'hui — rien. Le prix qui viendra
    /// est écrit juste en dessous : le cacher fait gagner un essai et perd la
    /// confiance au premier prélèvement.
    /// L'invite posée sur le clavier verrouillé.
    ///
    /// Un panneau plein cadre entrait en concurrence visuelle avec le trackpad
    /// juste en dessous : deux surfaces de même poids, et l'œil ne savait plus
    /// laquelle était l'écran. Une capsule compacte laisse le clavier flouté
    /// raconter ce qui est verrouillé, et le paywall complet s'ouvre en sheet.
    private var keyboardLock: some View {
        Button {
            present(.keyboard)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Premium.onGold)

                VStack(alignment: .leading, spacing: 1) {
                    Text(T("Unlock the keyboard", "Débloquer le clavier"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Premium.onGold)
                    Text(T("3 days free — $0.00 today", "3 jours gratuits — 0,00 $ aujourd'hui"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Premium.onGold.opacity(0.75))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Premium.goldSheen, in: Capsule())
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
    }

    private func present(_ feature: PremiumFeature) {
        paywallTrigger = feature
        showPaywall = true
    }
}
