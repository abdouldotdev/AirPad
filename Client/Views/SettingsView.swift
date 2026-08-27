import SwiftUI

struct SettingsView: View {
    @ObservedObject var client: NetworkClient
    @ObservedObject var macStore: PairedMacStore
    @ObservedObject var subscriptions: SubscriptionManager

    @Environment(\.dismiss) private var dismiss
    @AppStorage("advancedMode") private var advancedMode = false
    @AppStorage("keyboardLayout") private var keyboardLayoutRaw = KeyboardLayout.qwerty.rawValue
    @AppStorage("trackingSpeed") private var trackingSpeed: Double = 1.0
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true

    @State private var showPairing = false
    @State private var showPaywall = false
    @State private var paywallTrigger: PremiumFeature?

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                if !subscriptions.isSubscribed { upgradeSection }
                preferencesSection
                privacySection
                aboutSection
            }
            .navigationTitle(T("Settings", "Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(T("Done", "Terminé")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPairing) {
                PairingView(client: client, macStore: macStore, subscriptions: subscriptions) {
                    showPairing = false
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(subscriptions: subscriptions, trigger: paywallTrigger)
            }
            .onAppear { Analytics.shared.screen("settings") }
        }
    }

    private var connectionSection: some View {
        Section(T("Connection", "Connexion")) {
            ForEach(macStore.macs) { mac in
                Button {
                    macStore.selectedID = mac.id
                    client.connect(to: mac)
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mac.name)
                            Text(mac.host).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if macStore.selected?.id == mac.id {
                            Image(systemName: client.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(client.isConnected ? .green : .orange)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button(T("Remove", "Retirer"), role: .destructive) { macStore.remove(mac) }
                }
            }

            Button {
                // Le multi-Mac est réservé à l'abonnement ; le premier appairage est libre.
                if macStore.macs.isEmpty || subscriptions.has(.multiMac) {
                    showPairing = true
                } else {
                    paywallTrigger = .multiMac
                    showPaywall = true
                }
            } label: {
                Label(macStore.macs.isEmpty
                      ? T("Pair a Mac", "Appairer un Mac")
                      : T("Pair another Mac", "Appairer un autre Mac"),
                      systemImage: "plus.circle")
            }
        }
    }

    private var upgradeSection: some View {
        Section {
            Button {
                paywallTrigger = nil
                showPaywall = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Brand.accent,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Get AirPad Pro", "Passer à AirPad Pro")).font(.headline)
                        Text(T("Keyboard, F-keys, gestures and more", "Clavier, touches F, gestes et plus"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Button(T("Restore purchases", "Restaurer mes achats")) {
                Task { _ = await subscriptions.restore() }
            }
        }
    }

    private var preferencesSection: some View {
        Section(T("Preferences", "Préférences")) {
            Picker(T("Keyboard layout", "Disposition du clavier"), selection: $keyboardLayoutRaw) {
                ForEach(KeyboardLayout.allCases) { layout in
                    Text(layout.rawValue).tag(layout.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: keyboardLayoutRaw) { newValue in
                Analytics.shared.capture(Event.layoutChanged, ["layout": newValue])
                Analytics.shared.setPersonProperties(["keyboard_layout": newValue])
            }

            premiumToggle(
                title: T("Advanced mode (F1–F12)", "Mode avancé (F1–F12)"),
                feature: .functionRow,
                isOn: $advancedMode
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(T("Pointer speed", "Vitesse du curseur"))
                    Spacer()
                    if !subscriptions.has(.pointerSpeed) { proBadge }
                }
                Slider(value: $trackingSpeed, in: 0.2...4.0, step: 0.1)
                    .disabled(!subscriptions.has(.pointerSpeed))
                    .opacity(subscriptions.has(.pointerSpeed) ? 1 : 0.45)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !subscriptions.has(.pointerSpeed) else { return }
                paywallTrigger = .pointerSpeed
                showPaywall = true
            }
        }
    }

    private func premiumToggle(title: String, feature: PremiumFeature, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            if subscriptions.has(feature) {
                Toggle("", isOn: isOn).labelsHidden()
                    .onChange(of: isOn.wrappedValue) { value in
                        Analytics.shared.capture(Event.advancedModeToggled, ["enabled": value])
                    }
            } else {
                proBadge
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !subscriptions.has(feature) else { return }
            paywallTrigger = feature
            showPaywall = true
        }
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Brand.accent, in: Capsule())
            .foregroundStyle(.white)
    }

    private var privacySection: some View {
        Section {
            Toggle(T("Share anonymous usage data", "Partager des données d'usage anonymes"), isOn: $analyticsEnabled)
                .onChange(of: analyticsEnabled) { enabled in
                    enabled ? Analytics.shared.optIn() : Analytics.shared.optOut()
                }
        } footer: {
            Text(T("Never includes what you type, your IP address or your network name.",
                   "N'inclut jamais ce que vous tapez, votre adresse IP ni le nom de votre réseau."))
        }
    }

    private var aboutSection: some View {
        Section(T("About", "À propos")) {
            Link(destination: LegalLinks.macDownload) {
                Label(T("Download AirPad for Mac", "Télécharger AirPad pour Mac"), systemImage: "arrow.down.circle")
            }
            Link(destination: LegalLinks.privacy) {
                Label(T("Privacy Policy", "Politique de confidentialité"), systemImage: "hand.raised")
            }
            Link(destination: LegalLinks.terms) {
                Label(T("Terms of Use", "Conditions d'utilisation"), systemImage: "doc.text")
            }
            HStack {
                Text(T("Version", "Version"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
