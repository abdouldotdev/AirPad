import SwiftUI
import Network
import CoreGraphics
import AppKit

@main
struct AirPadMacApp: App {
    @StateObject private var server = MouseServer()
    
    var body: some Scene {
        // Fenêtre classique pour que l'UI soit bien visible au centre de l'écran
        WindowGroup {
            MacMainView(server: server)
        }
        .windowStyle(.hiddenTitleBar)
        
        // On garde l'icône dans la barre de menu en bonus
        MenuBarExtra(server.connectedDevice != nil ? "AirPad (Connecté)" : (server.isListening ? "AirPad (Attente)" : "AirPad"), systemImage: server.connectedDevice != nil ? "macbook.and.iphone" : "macbook") {
            VStack {
                Button(server.isListening ? "Arrêter le serveur" : "Démarrer l'appairage") {
                    server.isListening ? server.stop() : server.start()
                }
                Divider()
                Button("Quitter") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MacMainView: View {
    @ObservedObject var server: MouseServer
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(server.isListening ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: server.connectedDevice != nil ? "iphone.radiowaves.left.and.right" : "macbook.and.iphone")
                    .font(.system(size: 50))
                    .foregroundColor(server.isListening ? .blue : .gray)
            }
            
            VStack(spacing: 8) {
                Text("AirPad")
                    .font(.system(size: 32, weight: .bold))
                
                Text("Transformez votre iPhone en Trackpad & Clavier")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider().padding(.vertical, 8)
            
            if server.isListening {
                VStack(spacing: 16) {
                    if let ip = getLocalIPAddress() {
                        VStack(spacing: 4) {
                            Text("Entrez cette IP sur votre iPhone :")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            
                            Text(ip)
                                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    
                    if let device = server.connectedDevice {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connecté à : \(device)")
                                .font(.headline)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                    } else {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("En attente de connexion...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("Le serveur est inactif.")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            Spacer()
            
            Button(action: {
                if server.isListening {
                    server.stop()
                } else {
                    server.start()
                }
            }) {
                Text(server.isListening ? "Arrêter le serveur" : "Démarrer l'appairage")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(server.isListening ? .red : .blue)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 450, height: 500)
        .background(VisualEffectView().ignoresSafeArea())
    }
}

// Effet de transparence "Mac" en fond
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
            listener = try NWListener(using: .udp, on: port)
            listener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .userInteractive))
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
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                self?.processCommand(message)
            }
            if error == nil && self?.isListening == true {
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
