import SwiftUI
import AppKit
import ServiceManagement
import CoreImage.CIFilterBuiltins

// --- LOCALIZATION HELPER ---
func T(_ en: String, _ fr: String) -> String {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    return lang.hasPrefix("fr") ? fr : en
}

func generateQRCode(from string: String) -> NSImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let outputImage = filter.outputImage else { return nil }
    let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
}

@main
struct AirPadMacApp: App {
    @StateObject private var server = MouseServer()
    @StateObject private var accessibility = AccessibilityManager()

    private var menuBarTitle: String {
        if !accessibility.isTrusted { return T("AirPad (Permission needed)", "AirPad (Autorisation requise)") }
        if server.connectedDevice != nil { return T("AirPad (Connected)", "AirPad (Connecté)") }
        return server.isListening ? T("AirPad (Waiting)", "AirPad (Attente)") : "AirPad"
    }

    private var menuBarIcon: String {
        if !accessibility.isTrusted { return "exclamationmark.triangle" }
        return server.connectedDevice != nil ? "macbook.and.iphone" : "macbook"
    }

    var body: some Scene {
        WindowGroup {
            MacMainView(server: server, accessibility: accessibility)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra(menuBarTitle, systemImage: menuBarIcon) {
            if !accessibility.isTrusted {
                Button(T("Grant Accessibility access…", "Autoriser l'Accessibilité…")) {
                    accessibility.openSystemSettings()
                }
                Divider()
            }
            Button(server.isListening ? T("Stop Server", "Arrêter le serveur") : T("Start Pairing", "Démarrer l'appairage")) {
                server.isListening ? server.stop() : server.start()
            }
            Divider()
            Button(T("Quit", "Quitter")) { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Bannière affichée tant que l'autorisation Accessibilité manque. Sans elle,
/// le serveur « fonctionne » mais aucun clic n'atteint le système.
struct AccessibilityBanner: View {
    @ObservedObject var accessibility: AccessibilityManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(T("Accessibility access required", "Autorisation Accessibilité requise"))
                    .font(.headline)
            }
            Text(T("macOS blocks mouse and keyboard control until AirPad is allowed in System Settings › Privacy & Security › Accessibility.",
                   "macOS bloque le contrôle de la souris et du clavier tant qu'AirPad n'est pas autorisé dans Réglages Système › Confidentialité et sécurité › Accessibilité."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(T("Open Settings", "Ouvrir les Réglages")) { accessibility.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Button(T("Ask again", "Redemander")) { accessibility.requestAccess() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }
}

struct MacMainView: View {
    @ObservedObject var server: MouseServer
    @ObservedObject var accessibility: AccessibilityManager

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoStart") private var autoStart = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(server.isListening ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 90, height: 90)
                Image(systemName: server.connectedDevice != nil ? "iphone.radiowaves.left.and.right" : "macbook.and.iphone")
                    .font(.system(size: 36))
                    .foregroundColor(server.isListening ? .blue : .gray)
            }

            VStack(spacing: 4) {
                Text("AirPad").font(.system(size: 28, weight: .bold))
                Text(T("Turn your iPhone into a trackpad & keyboard", "Transformez votre iPhone en trackpad et clavier"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !accessibility.isTrusted {
                AccessibilityBanner(accessibility: accessibility)
            }

            Divider()

            if server.isListening {
                PairingPanel(server: server, pairing: server.pairing)
            } else {
                Text(T("Server is inactive.", "Le serveur est inactif."))
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding()
            }

            Button {
                server.isListening ? server.stop() : server.start()
            } label: {
                Text(server.isListening ? T("Stop Server", "Arrêter le serveur") : T("Start Pairing", "Démarrer l'appairage"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(server.isListening ? .red : .blue)
            .controlSize(.large)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(T("Settings", "Réglages")).font(.headline)

                Toggle(T("Launch AirPad at Mac startup", "Lancer AirPad au démarrage du Mac"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            print("Erreur SMAppService : \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Toggle(T("Start server automatically on launch", "Démarrer le serveur au lancement"), isOn: $autoStart)
                    .onChange(of: autoStart) { newValue in
                        if newValue && !server.isListening { server.start() }
                    }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 460)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if !accessibility.isTrusted { accessibility.requestAccess() }
            if autoStart && !server.isListening { server.start() }
        }
    }
}

struct PairingPanel: View {
    @ObservedObject var server: MouseServer
    @ObservedObject var pairing: PairingManager

    var body: some View {
        VStack(spacing: 12) {
            if let ip = getLocalIPAddress() {
                HStack(spacing: 20) {
                    if let qr = generateQRCode(from: pairing.pairingPayload(host: ip, port: server.port)) {
                        Image(nsImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 110, height: 110)
                            .cornerRadius(8)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Scan this code with AirPad on your iPhone", "Scannez ce code avec AirPad sur votre iPhone"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(T("or type it in manually:", "ou saisissez-le à la main :"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)

                        Text(ip)
                            .font(.system(size: 19, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .textSelection(.enabled)

                        HStack(spacing: 6) {
                            Text(T("Code", "Code")).font(.caption).foregroundColor(.secondary)
                            Text(pairing.displayCode)
                                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                                .textSelection(.enabled)
                            Button {
                                pairing.regenerate()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(T("Generate a new code and unpair every device",
                                    "Générer un nouveau code et dissocier tous les appareils"))
                        }
                    }
                }
            } else {
                Text(T("No Wi-Fi network detected.", "Aucun réseau Wi-Fi détecté."))
                    .foregroundColor(.orange)
            }

            if let device = server.connectedDevice {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(T("Connected to: \(device)", "Connecté à : \(device)")).font(.headline)
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text(T("Waiting for connection…", "En attente de connexion…")).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

func getLocalIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr = ifaddr
    while ptr != nil {
        defer { ptr = ptr?.pointee.ifa_next }
        guard let interface = ptr?.pointee else { continue }
        guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: interface.ifa_name)
        guard name == "en0" || name == "en1" else { continue }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
        address = String(cString: hostname)
        break
    }
    return address
}
