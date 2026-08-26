import Foundation
import Network
import UIKit

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    /// Le Mac a refusé le code d'appairage : il faut rescanner, pas réessayer.
    case rejected
    case failed(String)

    var isConnected: Bool { self == .connected }
}

@MainActor
final class NetworkClient: ObservableObject {
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var currentMac: PairedMac?

    var isConnected: Bool { state.isConnected }

    /// Remonté à l'analytique (jamais l'IP, seulement l'issue et le délai).
    var onConnectionEvent: ((String, [String: Any]) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "dev.abdouldotdev.airpad.tcp", qos: .userInteractive)
    private var receiveBuffer = Data()

    private var heartbeat: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var lastPong = Date()
    private var attempt = 0
    private var connectStartedAt = Date()
    private var shouldStayConnected = false

    private let deviceName = UIDevice.current.name

    // MARK: - Cycle de vie

    func connect(to mac: PairedMac) {
        disconnect(keepAlive: true)
        currentMac = mac
        shouldStayConnected = true
        connectStartedAt = Date()
        openConnection(to: mac)
    }

    func disconnect(keepAlive: Bool = false) {
        shouldStayConnected = keepAlive
        heartbeat?.cancel(); heartbeat = nil
        reconnect?.cancel(); reconnect = nil
        connection?.cancel(); connection = nil
        receiveBuffer.removeAll()
        if !keepAlive {
            state = .idle
            currentMac = nil
        }
    }

    private func openConnection(to mac: PairedMac) {
        guard let port = NWEndpoint.Port(rawValue: mac.port) else { return }
        state = attempt == 0 ? .connecting : .reconnecting

        let options = NWProtocolTCP.Options()
        options.noDelay = true
        options.enableKeepalive = true
        options.keepaliveIdle = 5
        options.keepaliveInterval = 2
        options.keepaliveCount = 3

        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(mac.host), port: port),
            using: NWParameters(tls: nil, tcp: options)
        )
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                switch newState {
                case .ready:
                    // Rien n'est utilisable tant que le Mac n'a pas validé le code.
                    self.send("AUTH:\(mac.token)")
                    self.receiveLoop(on: connection)
                case .failed(let error):
                    self.handleDrop(reason: "failed", detail: error.localizedDescription)
                case .cancelled:
                    break
                case .waiting(let error):
                    // .waiting signifie « le Mac est injoignable » : l'ancien code
                    // restait bloqué ici en affichant « Connecté ».
                    self.handleDrop(reason: "waiting", detail: error.localizedDescription)
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Réception

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.drainBuffer()
                }
                if error != nil || isComplete {
                    self.handleDrop(reason: isComplete ? "closed" : "error",
                                    detail: error?.localizedDescription ?? "peer closed")
                    return
                }
                self.receiveLoop(on: connection)
            }
        }
    }

    private func drainBuffer() {
        let newline = UInt8(ascii: "\n")
        while let index = receiveBuffer.firstIndex(of: newline) {
            let line = receiveBuffer[receiveBuffer.startIndex..<index]
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...index)
            guard let text = String(data: line, encoding: .utf8) else { continue }
            handle(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if receiveBuffer.count > 65_536 { receiveBuffer.removeAll() }
    }

    private func handle(_ message: String) {
        switch message {
        case "OK":
            attempt = 0
            lastPong = Date()
            state = .connected
            send("INIT:\(deviceName)")
            startHeartbeat()
            onConnectionEvent?("connection_established", [
                "duration_ms": Int(Date().timeIntervalSince(connectStartedAt) * 1000)
            ])
        case "DENIED":
            // Un code invalide ne se répare pas en réessayant.
            shouldStayConnected = false
            state = .rejected
            onConnectionEvent?("connection_rejected", [:])
        case "PONG":
            lastPong = Date()
        default:
            break
        }
    }

    // MARK: - Heartbeat et reconnexion

    /// Un Mac qui disparaît (veille, Wi-Fi coupé) ne ferme pas toujours la connexion :
    /// sans ce battement, l'app restait affichée « Connecté » indéfiniment.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.state.isConnected else { return }
                if Date().timeIntervalSince(self.lastPong) > 6 {
                    self.handleDrop(reason: "timeout", detail: "no pong")
                    return
                }
                self.send("PING")
            }
        }
    }

    private func handleDrop(reason: String, detail: String) {
        guard state != .rejected else { return }
        heartbeat?.cancel(); heartbeat = nil
        connection?.cancel(); connection = nil
        receiveBuffer.removeAll()

        let wasConnected = state.isConnected
        if wasConnected {
            onConnectionEvent?("connection_lost", ["reason": reason])
        }

        guard shouldStayConnected, let mac = currentMac else {
            state = .failed(detail)
            return
        }
        scheduleReconnect(to: mac)
    }

    private func scheduleReconnect(to mac: PairedMac) {
        reconnect?.cancel()
        state = .reconnecting
        attempt += 1
        // Palier progressif : inutile de marteler un Mac éteint.
        let delay = min(pow(1.6, Double(min(attempt, 8))), 20.0)
        reconnect = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.shouldStayConnected else { return }
            self.openConnection(to: mac)
        }
    }

    // MARK: - Envoi

    private func send(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func sendIfConnected(_ message: String) {
        guard state.isConnected else { return }
        send(message)
    }

    func sendMove(dx: CGFloat, dy: CGFloat) { sendIfConnected("M:\(dx):\(dy)") }
    func sendScroll(dx: CGFloat, dy: CGFloat) { sendIfConnected("S:\(dx):\(dy)") }
    func sendClick() { sendIfConnected("C:1") }
    func sendRightClick() { sendIfConnected("R:1") }
    func sendKey(code: UInt16, isDown: Bool, flags: UInt64 = 0) {
        sendIfConnected("K:\(code):\(isDown ? 1 : 0):\(flags)")
    }
}
