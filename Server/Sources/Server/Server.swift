import SwiftUI
import Network
import CoreGraphics
import AppKit

@main
struct AirPadMacApp: App {
    @StateObject private var server = MouseServer()
    
    var body: some Scene {
        MenuBarExtra(server.connectedDevice != nil ? "AirPad (Connecté)" : (server.isListening ? "AirPad (Attente)" : "AirPad"), systemImage: server.connectedDevice != nil ? "macbook.and.iphone" : "macbook") {
            VStack(alignment: .leading) {
                Text("AirPad Serveur")
                    .font(.headline)
                
                Divider()
                
                if server.isListening {
                    if let device = server.connectedDevice {
                        Text("✅ Connecté à :")
                        Text(device)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Text("⏳ En attente de connexion...")
                            .foregroundColor(.gray)
                        if let ip = getLocalIPAddress() {
                            Text("Entrez cette IP sur l'iPhone :")
                                .font(.caption)
                            Text(ip)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                } else {
                    Text("🔴 Serveur inactif")
                        .foregroundColor(.gray)
                }
                
                Divider()
                
                Button(server.isListening ? "Arrêter le serveur" : "Démarrer l'appairage") {
                    if server.isListening {
                        server.stop()
                    } else {
                        server.start()
                    }
                }
                
                Divider()
                
                Button("Quitter AirPad") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class MouseServer: ObservableObject, @unchecked Sendable {
    var listener: NWListener?
    
    @Published var connectedDevice: String? = nil
    @Published var isListening: Bool = false
    
    var currentMouseLocation: CGPoint {
        guard let event = CGEvent(source: nil) else { return .zero }
        return event.location
    }
    
    // On ne démarre plus le serveur à l'initialisation
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
        } catch {
            print("Erreur: \(error)")
        }
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
                DispatchQueue.main.async {
                    self.connectedDevice = deviceName
                }
            }
        case "M":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) {
                moveMouse(dx: dx, dy: dy)
            }
        case "C":
            clickMouse()
        case "R":
            rightClick()
        case "S":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) {
                scrollMouse(dx: dx, dy: dy)
            }
        case "K":
            if parts.count == 3, let code = UInt16(parts[1]), let state = Int(parts[2]) {
                pressKey(keyCode: code, down: state == 1)
            }
        default:
            break
        }
    }
    
    private func pressKey(keyCode: UInt16, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.post(tap: .cghidEventTap)
    }
    
    private func moveMouse(dx: Double, dy: Double) {
        let sensitivity = 1.5
        var location = currentMouseLocation
        location.x += CGFloat(dx * sensitivity)
        location.y += CGFloat(dy * sensitivity)
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
    }
    
    private func clickMouse() {
        let location = currentMouseLocation
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }
    
    private func rightClick() {
        let location = currentMouseLocation
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: location, mouseButton: .right)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: location, mouseButton: .right)
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }
    
    private func scrollMouse(dx: Double, dy: Double) {
        let sensitivity = 3.0
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy * sensitivity), wheel2: Int32(dx * sensitivity), wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
}

// Helper pour afficher l'IP locale afin de faciliter la configuration
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
