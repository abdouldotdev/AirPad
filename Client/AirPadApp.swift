import SwiftUI

/// Clés d'API injectées à la compilation (voir project.yml).
/// Une clé absente laisse simplement la fonctionnalité inactive, sans planter l'app.
enum AppConfig {
    static var revenueCatKey: String {
        Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
    }
    static var postHogKey: String {
        Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String ?? ""
    }
    static var postHogHost: String {
        Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String ?? "https://eu.i.posthog.com"
    }
}

@main
struct AirPadApp: App {
    @StateObject private var client = NetworkClient()
    @StateObject private var macStore = PairedMacStore()
    @StateObject private var subscriptions = SubscriptionManager()

    init() {
        #if DEBUG
        CaptureMode.apply()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client, macStore: macStore, subscriptions: subscriptions)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @ObservedObject var client: NetworkClient
    @ObservedObject var macStore: PairedMacStore
    @ObservedObject var subscriptions: SubscriptionManager

    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true
    @State private var showCaptureSheet = false

    var body: some View {
        Group {
            if !didFinishOnboarding {
                OnboardingView {
                    withAnimation { didFinishOnboarding = true }
                }
            } else if macStore.macs.isEmpty {
                NavigationStack {
                    PairingView(client: client, macStore: macStore, subscriptions: subscriptions) {}
                }
            } else {
                AirPadView(client: client, macStore: macStore, subscriptions: subscriptions)
            }
        }
        .task { await bootstrap() }
        #if DEBUG
        .sheet(isPresented: $showCaptureSheet) { captureSheet }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private var captureSheet: some View {
        switch CaptureMode.screen {
        case "paywall":
            PaywallView(subscriptions: subscriptions, trigger: .keyboard)
        case "settings", "settings-pro":
            SettingsView(client: client, macStore: macStore, subscriptions: subscriptions)
        default:
            EmptyView()
        }
    }
    #endif

    private func bootstrap() async {
        #if DEBUG
        if ["paywall", "settings", "settings-pro"].contains(CaptureMode.screen ?? "") {
            showCaptureSheet = true
        }
        #endif
        if analyticsEnabled {
            Analytics.shared.configure(apiKey: AppConfig.postHogKey, host: AppConfig.postHogHost)
        }
        subscriptions.configure(apiKey: AppConfig.revenueCatKey)
        // Un même identifiant des deux côtés permet de recoller les achats à l'usage.
        subscriptions.identify(analyticsID: Analytics.shared.distinctID)

        subscriptions.onEvent = { name, properties in
            Analytics.shared.capture(name, properties)
        }
        client.onConnectionEvent = { name, properties in
            Analytics.shared.capture(name, properties)
        }

        if let mac = macStore.selected, client.state == .idle {
            client.connect(to: mac)
        }
        await subscriptions.refresh()
        Analytics.shared.setPersonProperties([
            "subscription_status": subscriptions.isSubscribed ? "active" : "free"
        ])
    }
}
