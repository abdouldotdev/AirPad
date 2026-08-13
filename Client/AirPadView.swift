import SwiftUI
import Network

class NetworkClient: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "UDP Client Queue", qos: .userInteractive)
    
    @Published var isConnected: Bool = false
    
    func connect(to ipAddress: String, port: NWEndpoint.Port = 8080) {
        let host = NWEndpoint.Host(ipAddress)
        connection = NWConnection(host: host, port: port, using: .udp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                case .failed(_), .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        connection?.start(queue: queue)
    }
    
    func sendMove(dx: CGFloat, dy: CGFloat) {
        send("M:\(dx):\(dy)")
    }
    
    func sendClick() {
        send("C:1")
    }
    
    func sendKey(code: UInt16, isDown: Bool) {
        send("K:\(code):\(isDown ? 1 : 0)")
    }
    
    private func send(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }
}

// Modèle de touche Mac
struct MacKey: Identifiable {
    let id = UUID()
    let label: String
    let code: UInt16
    var widthMultiplier: CGFloat = 1.0
    var isDark: Bool = false
}

// Vue principale : Trackpad en haut, Clavier Physique en bas
struct AirPadView: View {
    @StateObject private var client = NetworkClient()
    @State private var previousLocation: CGPoint?
    @AppStorage("serverIP") private var serverIP: String = "192.168.1.50"
    @State private var showSettings = false
    
    // Définition du clavier QWERTY (Mac Native Keycodes)
    let row1 = [
        MacKey(label: "Q", code: 12), MacKey(label: "W", code: 13), MacKey(label: "E", code: 14), MacKey(label: "R", code: 15), MacKey(label: "T", code: 17),
        MacKey(label: "Y", code: 16), MacKey(label: "U", code: 32), MacKey(label: "I", code: 34), MacKey(label: "O", code: 31), MacKey(label: "P", code: 35)
    ]
    let row2 = [
        MacKey(label: "A", code: 0), MacKey(label: "S", code: 1), MacKey(label: "D", code: 2), MacKey(label: "F", code: 3), MacKey(label: "G", code: 5),
        MacKey(label: "H", code: 4), MacKey(label: "J", code: 38), MacKey(label: "K", code: 40), MacKey(label: "L", code: 37), MacKey(label: "Ret", code: 36, widthMultiplier: 1.5, isDark: true)
    ]
    let row3 = [
        MacKey(label: "Z", code: 6), MacKey(label: "X", code: 7), MacKey(label: "C", code: 8), MacKey(label: "V", code: 9), MacKey(label: "B", code: 11),
        MacKey(label: "N", code: 45), MacKey(label: "M", code: 46), MacKey(label: ",", code: 43), MacKey(label: "⌫", code: 51, widthMultiplier: 2.0, isDark: true)
    ]
    let row4 = [
        MacKey(label: "fn", code: 63, isDark: true), MacKey(label: "⌃", code: 59, isDark: true), MacKey(label: "⌥", code: 58, isDark: true), MacKey(label: "⌘", code: 55, widthMultiplier: 1.2, isDark: true),
        MacKey(label: "", code: 49, widthMultiplier: 4.5), // Espace
        MacKey(label: "⌘", code: 54, widthMultiplier: 1.2, isDark: true), MacKey(label: "⌥", code: 61, isDark: true)
    ]
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ZONE TRACKPAD (Haut)
                ZStack {
                    // Texture de verre dépoli "Apple" pour le trackpad
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .overlay(
                            LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.05), Color.clear]), startPoint: .top, endPoint: .bottom)
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    if let prev = previousLocation {
                                        let dx = value.location.x - prev.x
                                        let dy = value.location.y - prev.y
                                        client.sendMove(dx: dx, dy: dy)
                                    }
                                    previousLocation = value.location
                                }
                                .onEnded { _ in
                                    previousLocation = nil
                                }
                        )
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                client.sendClick()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        )
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { showSettings.toggle() }) {
                                Image(systemName: client.isConnected ? "macbook.and.iphone" : "wifi.slash")
                                    .foregroundColor(client.isConnected ? .white.opacity(0.8) : .red)
                                    .padding(12)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .padding()
                        }
                        Spacer()
                    }
                }
                .frame(height: geo.size.height * 0.5) // Prend la moitié de l'écran
                
                // ZONE CLAVIER PHYSIQUE (Bas)
                ZStack {
                    // Fond aluminium sombre du clavier (Space Gray)
                    Color(white: 0.18).edgesIgnoringSafeArea(.bottom)
                    
                    VStack(spacing: 8) {
                        KeyboardRow(keys: row1, client: client)
                        KeyboardRow(keys: row2, client: client)
                        KeyboardRow(keys: row3, client: client)
                        KeyboardRow(keys: row4, client: client)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client, serverIP: $serverIP)
        }
        .onAppear {
            client.connect(to: serverIP)
        }
    }
}

// Ligne de clavier
struct KeyboardRow: View {
    let keys: [MacKey]
    let client: NetworkClient
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys) { key in
                PhysicalKeyView(key: key, client: client)
            }
        }
    }
}

// Design ultra-réaliste d'une touche physique de MacBook
struct PhysicalKeyView: View {
    let key: MacKey
    let client: NetworkClient
    
    @State private var isPressed = false
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Ombre sous la touche (effet 3D)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.6))
                    .offset(y: isPressed ? 1 : 3)
                
                // Surface de la touche
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                key.isDark ? Color(white: 0.2) : Color(white: 0.35),
                                key.isDark ? Color(white: 0.15) : Color(white: 0.28)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .offset(y: isPressed ? 2 : 0) // Effet d'enfoncement
                
                // Label de la touche
                Text(key.label)
                    .font(.system(size: key.label.count > 1 ? 14 : 18, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                    .offset(y: isPressed ? 2 : 0)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            client.sendKey(code: key.code, isDown: true)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        client.sendKey(code: key.code, isDown: false)
                    }
            )
        }
        .frame(width: (UIScreen.main.bounds.width - 66) / 10 * key.widthMultiplier, height: 48)
    }
}

struct SettingsView: View {
    @ObservedObject var client: NetworkClient
    @Binding var serverIP: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connexion au Mac")) {
                    TextField("IP Locale (ex: 192.168.1.50)", text: $serverIP)
                        .keyboardType(.decimalPad)
                    
                    Button("Connecter") {
                        client.connect(to: serverIP)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle("Réglages AirPad")
        }
        .presentationDetents([.medium])
    }
}
