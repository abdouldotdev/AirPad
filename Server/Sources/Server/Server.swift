import SwiftUI
import Network
import CoreGraphics
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
    if let outputImage = filter.outputImage {
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
        }
    }
    return nil
}

@main
struct AirPadMacApp: App {
    @StateObject private var server = MouseServer()
    
    var body: some Scene {
        WindowGroup {
            MacMainView(server: server)
        }
        .windowStyle(.hiddenTitleBar)
        
        MenuBarExtra(server.connectedDevice != nil ? T("AirPad (Connected)", "AirPad (Connecté)") : (server.isListening ? T("AirPad (Waiting)", "AirPad (Attente)") : "AirPad"), systemImage: server.connectedDevice != nil ? "macbook.and.iphone" : "macbook") {
            VStack {
                Button(server.isListening ? T("Stop Server", "Arrêter le serveur") : T("Start Pairing", "Démarrer l'appairage")) {
                    server.isListening ? server.stop() : server.start()
                }
                Divider()
                Button(T("Quit", "Quitter")) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MacMainView: View {
    @ObservedObject var server: MouseServer
    
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoStart") private var autoStart = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(server.isListening ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: server.connectedDevice != nil ? "iphone.radiowaves.left.and.right" : "macbook.and.iphone")
                    .font(.system(size: 40))
                    .foregroundColor(server.isListening ? .blue : .gray)
            }
            
            VStack(spacing: 4) {
                Text("AirPad")
                    .font(.system(size: 28, weight: .bold))
                Text(T("Transform your iPhone into a Trackpad & Keyboard", "Transformez votre iPhone en Trackpad & Clavier"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            if server.isListening {
                VStack(spacing: 12) {
                    if let ip = getLocalIPAddress() {
                        HStack(spacing: 20) {
                            if let qr = generateQRCode(from: ip) {
                                Image(nsImage: qr)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(T("Scan QR or enter IP on iPhone:", "Scannez le QR ou entrez l'IP :"))
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                
                                Text(ip)
                                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    if let device = server.connectedDevice {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(T("Connected to: \(device)", "Connecté à : \(device)"))
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text(T("Waiting for connection...", "En attente de connexion..."))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(T("Server is inactive.", "Le serveur est inactif."))
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            Button(action: {
                if server.isListening {
                    server.stop()
                } else {
                    server.start()
                }
            }) {
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
                        } catch { print("Erreur SMAppService : \(error)") }
                    }
                
                Toggle(T("Start server automatically on launch", "Activer le serveur automatiquement au lancement"), isOn: $autoStart)
                    .onChange(of: autoStart) { newValue in
                        if newValue && !server.isListening { server.start() }
                    }
            }
            .font(.callout)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(30)
        .frame(width: 450, height: 600)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if autoStart && !server.isListening { server.start() }
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

final class MouseServer: ObservableObject, @unchecked Sendable {
    var listener: NWListener?
    @Published var connectedDevice: String? = nil
    @Published var isListening: Bool = false
    
    var currentMouseLocation: CGPoint {
        guard let event = CGEvent(source: nil) else { return .zero }
        return event.location
    }
    
    init() {}
    
    func start(port: NWEndpoint.Port = 8080) {
        do {
            listener = try NWListener(using: .tcp, on: 8080)
            listener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                self?.receiveLoop(on: connection)
            }
            listener?.start(queue: .main)
            DispatchQueue.main.async {
                self.isListening = true
                self.connectedDevice = nil
            }
        } catch { print("Erreur: \(error)") }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isListening = false
            self.connectedDevice = nil
        }
    }
    
    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                let commands = message.split(separator: "\n")
                for command in commands {
                    self?.processCommand(String(command))
                }
            }
            if error == nil && self?.isListening == true && !isComplete {
                self?.receiveLoop(on: connection)
            }
        }
    }
    
    private func processCommand(_ command: String) {
        let parts = command.split(separator: ":")
        guard let action = parts.first else { return }
        
        switch action {
        case "INIT":
            if parts.count >= 2 {
                let deviceName = parts.dropFirst().joined(separator: ":")
                DispatchQueue.main.async { self.connectedDevice = deviceName }
            }
        case "M":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) { moveMouse(dx: dx, dy: dy) }
        case "C":
            clickMouse()
        case "R":
            rightClick()
        case "S":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) { scrollMouse(dx: dx, dy: dy) }
        case "K":
            if parts.count == 3, let code = UInt16(parts[1]), let state = Int(parts[2]) { pressKey(keyCode: code, down: state == 1) }
        default:
            break
        }
    }
    
    private func pressKey(keyCode: UInt16, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.post(tap: .cghidEventTap)
    }
    private func moveMouse(dx: Double, dy: Double) {
        var location = currentMouseLocation
        location.x += CGFloat(dx * 1.5)
        location.y += CGFloat(dy * 1.5)
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
    }
    private func clickMouse() {
        let location = currentMouseLocation
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap); upEvent?.post(tap: .cghidEventTap)
    }
    private func rightClick() {
        let location = currentMouseLocation
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: location, mouseButton: .right)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: location, mouseButton: .right)
        downEvent?.post(tap: .cghidEventTap); upEvent?.post(tap: .cghidEventTap)
    }
    private func scrollMouse(dx: Double, dy: Double) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy * 3.0), wheel2: Int32(dx * 3.0), wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
}

func getLocalIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { return nil }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        freeifaddrs(ifaddr)
    }
    return address
}
