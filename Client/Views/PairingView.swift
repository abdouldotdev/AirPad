import SwiftUI

/// Écran d'appairage : scan du QR affiché par le Mac, ou saisie manuelle IP + code.
struct PairingView: View {
    @ObservedObject var client: NetworkClient
    @ObservedObject var macStore: PairedMacStore
    @ObservedObject var subscriptions: SubscriptionManager

    var onPaired: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPermission: CameraPermission = .unknown
    @State private var manualHost = ""
    @State private var manualCode = ""
    @State private var errorMessage: String?
    @State private var showManualEntry = false
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(T("Pair with your Mac", "Appairez votre Mac"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(T("Open AirPad on your Mac and press Start Pairing.",
                           "Ouvrez AirPad sur votre Mac et appuyez sur Démarrer l'appairage."))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                scannerCard

                Button {
                    withAnimation { showManualEntry.toggle() }
                } label: {
                    Label(showManualEntry
                          ? T("Hide manual entry", "Masquer la saisie manuelle")
                          : T("Or enter IP and code manually", "Ou saisissez l'IP et le code à la main"),
                          systemImage: "keyboard")
                        .font(.subheadline)
                }

                if showManualEntry { manualEntryCard }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Divider().padding(.vertical, 4)

                VStack(spacing: 8) {
                    Text(T("Don't have the Mac app yet?", "Vous n'avez pas encore l'app Mac ?"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: LegalLinks.macDownload) {
                        Label(T("Download AirPad for Mac", "Télécharger AirPad pour Mac"),
                              systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            startedAt = Date()
            Analytics.shared.capture(Event.pairingStarted)
            Analytics.shared.screen("pairing")
        }
    }

    private var scannerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)

            switch cameraPermission {
            case .denied:
                // Un rectangle noir muet laissait l'utilisateur sans explication.
                VStack(spacing: 12) {
                    Image(systemName: "video.slash.fill").font(.title)
                    Text(T("Camera access is off", "L'accès à la caméra est désactivé"))
                        .font(.subheadline.weight(.semibold))
                    Text(T("Allow the camera to scan the pairing code, or enter it by hand below.",
                           "Autorisez la caméra pour scanner le code, ou saisissez-le à la main ci-dessous."))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button(T("Open Settings", "Ouvrir les Réglages")) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(20)
            default:
                QRCodeScannerView(
                    onPermissionChange: { permission in
                        cameraPermission = permission
                        if permission == .denied {
                            Analytics.shared.capture(Event.pairingCameraDenied)
                        }
                    },
                    onFound: handleScan
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 170, height: 170)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
        }
        .frame(height: 280)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Mac IP address", "Adresse IP du Mac"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("192.168.1.50", text: $manualHost)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

            Text(T("Pairing code", "Code d'appairage"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("A3F9-K2M7", text: $manualCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

            Button {
                submitManual()
            } label: {
                Text(T("Connect", "Connecter"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func handleScan(_ raw: String) {
        guard let mac = PairingPayload.parse(raw) else {
            Analytics.shared.capture(Event.pairingScanFailed, ["reason": "unrecognized_payload"])
            errorMessage = T("That code isn't an AirPad pairing code.",
                             "Ce code n'est pas un code d'appairage AirPad.")
            return
        }
        Analytics.shared.capture(Event.pairingScanSucceeded)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        finish(with: mac, method: "qr")
    }

    private func submitManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        let code = PairingPayload.normalizeCode(manualCode)
        Analytics.shared.capture(Event.pairingManualSubmitted)

        guard PairingPayload.isValidIPv4(host) else {
            errorMessage = T("Enter a valid IP address, like 192.168.1.50.",
                             "Saisissez une adresse IP valide, par exemple 192.168.1.50.")
            return
        }
        guard code.count == 8 else {
            errorMessage = T("The pairing code has 8 characters.",
                             "Le code d'appairage comporte 8 caractères.")
            return
        }
        finish(with: PairedMac(name: "Mac", host: host, port: 8080, token: code), method: "manual")
    }

    private func finish(with mac: PairedMac, method: String) {
        errorMessage = nil
        macStore.upsert(mac, allowMultiple: subscriptions.has(.multiMac))
        client.connect(to: mac)
        Analytics.shared.setPersonProperties([
            "pairing_method": method,
            "paired_mac_id": mac.anonymousID
        ])
        Analytics.shared.capture(Event.firstConnectionSucceeded, [
            "method": method,
            "seconds_to_pair": Int(Date().timeIntervalSince(startedAt))
        ])
        onPaired()
    }
}
