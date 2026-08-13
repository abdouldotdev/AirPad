import Foundation
import Network
import CoreGraphics

@main
struct Server {
    static func main() {
        let server = MouseServer()
        server.start()
        RunLoop.main.run()
    }
}

class MouseServer {
    var listener: NWListener?
    
    var currentMouseLocation: CGPoint {
        guard let event = CGEvent(source: nil) else { return .zero }
        return event.location
    }
    
    func start(port: NWEndpoint.Port = 8080) {
        do {
            listener = try NWListener(using: .udp, on: port)
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("Nouvelle connexion entrante: \(connection.endpoint)")
                connection.start(queue: .global(qos: .userInteractive))
                self?.receiveLoop(on: connection)
            }
            
            listener?.start(queue: .main)
            print("AirPad Serveur démarré sur le port \(port). En attente de l'iPhone...")
            
        } catch {
            print("Erreur de démarrage du serveur: \(error)")
        }
    }
    
    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                self?.processCommand(message)
            }
            
            if error == nil {
                self?.receiveLoop(on: connection)
            }
        }
    }
    
    private func processCommand(_ command: String) {
        let parts = command.split(separator: ":")
        guard let action = parts.first else { return }
        
        switch action {
        case "M": // M:dx:dy (Move Mouse)
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) {
                moveMouse(dx: dx, dy: dy)
            }
        case "C": // C:1 (Click)
            clickMouse()
        default:
            break
        }
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
}
