import SwiftUI
import Network
import CoreGraphics

@MainActor
final class MouseServer: ObservableObject {
    @Published private(set) var connectedDevice: String? = nil
    @Published private(set) var isListening: Bool = false
    @Published private(set) var port: UInt16 = 8080

    private var listener: NWListener?
    /// Connexion active unique. Un trackpad piloté par deux téléphones à la fois donne
    /// un curseur qui saute : la seconde connexion est refusée tant que la première vit.
    private var activeConnection: NWConnection?
    /// Reliquat des paquets TCP précédents. Sans lui, une commande coupée en deux
    /// paquets (« M:12.5 » | « :3.0\n ») est perdue ou, pire, interprétée de travers.
    private var receiveBuffer = Data()

    private var currentMouseLocation: CGPoint {
        guard let event = CGEvent(source: nil) else { return .zero }
        return event.location
    }

    // MARK: - Cycle de vie

    func start(port requestedPort: UInt16 = 8080) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: requestedPort) else {
            print("Port invalide : \(requestedPort)")
            return
        }

        let options = NWProtocolTCP.Options()
        // Détecte un client parti sans FIN (Wi-Fi coupé, téléphone en veille prolongée).
        options.enableKeepalive = true
        options.keepaliveIdle = 5
        options.keepaliveInterval = 2
        options.keepaliveCount = 3
        options.noDelay = true

        do {
            let listener = try NWListener(using: NWParameters(tls: nil, tcp: options), on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                    case .failed(let error), .waiting(let error):
                        print("Listener en erreur : \(error)")
                        self?.stop()
                    case .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            self.port = requestedPort
            listener.start(queue: .main)
        } catch {
            print("Impossible d'ouvrir le port \(requestedPort) : \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        // Sans cette ligne, arrêter le serveur laissait la connexion en cours vivante
        // et le téléphone continuait de piloter le Mac.
        activeConnection?.cancel()
        activeConnection = nil
        receiveBuffer.removeAll()
        isListening = false
        connectedDevice = nil
    }

    // MARK: - Connexions

    private func accept(_ connection: NWConnection) {
        guard activeConnection == nil else {
            connection.cancel()
            return
        }
        activeConnection = connection
        receiveBuffer.removeAll()

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed, .cancelled:
                    self?.disconnect(connection)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        receiveLoop(on: connection)
    }

    private func disconnect(_ connection: NWConnection) {
        guard activeConnection === connection else { return }
        activeConnection = nil
        receiveBuffer.removeAll()
        // L'ancien code n'écoutait aucun changement d'état : « Connecté à iPhone »
        // restait affiché indéfiniment après le départ du téléphone.
        connectedDevice = nil
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.activeConnection === connection else { return }

                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.drainBuffer()
                }

                if error != nil || isComplete {
                    connection.cancel()
                    self.disconnect(connection)
                    return
                }
                self.receiveLoop(on: connection)
            }
        }
    }

    /// Extrait toutes les lignes complètes du tampon et conserve le reliquat.
    private func drainBuffer() {
        let newline = UInt8(ascii: "\n")
        while let index = receiveBuffer.firstIndex(of: newline) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<index]
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...index)
            if let line = String(data: lineData, encoding: .utf8) {
                processCommand(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        // Garde-fou : un client défaillant qui n'enverrait jamais de « \n » ne doit pas
        // faire grossir le tampon sans limite.
        if receiveBuffer.count > 1_048_576 { receiveBuffer.removeAll() }
    }

    private func send(_ message: String, on connection: NWConnection) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Protocole

    private func processCommand(_ command: String) {
        guard !command.isEmpty else { return }
        let parts = command.split(separator: ":", omittingEmptySubsequences: false)
        guard let action = parts.first else { return }

        switch action {
        case "INIT":
            guard parts.count >= 2 else { return }
            connectedDevice = parts.dropFirst().joined(separator: ":")
        case "PING":
            if let connection = activeConnection { send("PONG", on: connection) }
        case "M":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) { moveMouse(dx: dx, dy: dy) }
        case "S":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) { scrollMouse(dx: dx, dy: dy) }
        case "C":
            clickMouse()
        case "R":
            rightClick()
        case "K":
            if parts.count >= 3, let code = UInt16(parts[1]), let state = Int(parts[2]) {
                let flags = parts.count >= 4 ? (UInt64(parts[3]) ?? 0) : 0
                pressKey(keyCode: code, down: state == 1, flags: flags)
            }
        default:
            break
        }
    }

    // MARK: - Injection d'événements

    private func pressKey(keyCode: UInt16, down: Bool, flags: UInt64) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        event.flags = CGEventFlags(rawValue: flags)
        event.post(tap: .cghidEventTap)
    }

    private func moveMouse(dx: Double, dy: Double) {
        var location = currentMouseLocation
        location.x += CGFloat(dx * 1.5)
        location.y += CGFloat(dy * 1.5)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main else { return }
        // Sans bornage, un geste rapide « perd » le curseur hors écran et il faut
        // plusieurs allers-retours pour le ramener.
        let bounds = screen.frame
        location.x = min(max(location.x, bounds.minX), bounds.maxX - 1)
        location.y = min(max(location.y, bounds.minY), bounds.maxY - 1)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func clickMouse() {
        let location = currentMouseLocation
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func rightClick() {
        let location = currentMouseLocation
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: location, mouseButton: .right)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: location, mouseButton: .right)?.post(tap: .cghidEventTap)
    }

    private func scrollMouse(dx: Double, dy: Double) {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy * 3.0), wheel2: Int32(dx * 3.0), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }
}
