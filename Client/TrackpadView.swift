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
        let message = "M:\(dx):\(dy)"
        send(message)
    }
    
    func sendClick() {
        send("C:1")
    }
    
    private func send(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }
}

struct TrackpadView: View {
    @StateObject private var client = NetworkClient()
    @State private var previousLocation: CGPoint?
    @AppStorage("serverIP") private var serverIP: String = "192.168.1.50"
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            // Fond noir profond (OLED) typique d'Apple pour économiser la batterie
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Zone Trackpad Invisible prenant tout l'écran
            Color.white.opacity(0.001)
                .edgesIgnoringSafeArea(.all)
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
                    TapGesture()
                        .onEnded {
                            client.sendClick()
                            // Retour Haptique très léger "Apple Style"
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                )
            
            // Indicateurs et Boutons flottants
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        showSettings.toggle()
                        let generator = UISelectionFeedbackGenerator()
                        generator.selectionChanged()
                    }) {
                        Image(systemName: client.isConnected ? "macbook.and.iphone" : "wifi.exclamationmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(client.isConnected ? .white : .orange)
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client, serverIP: $serverIP)
        }
        .onAppear {
            client.connect(to: serverIP)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var client: NetworkClient
    @Binding var serverIP: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connexion au Mac").textCase(nil)) {
                    HStack {
                        Text("IP Locale")
                        Spacer()
                        TextField("ex: 192.168.1.50", text: $serverIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    
                    Button(action: {
                        client.connect(to: serverIP)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Connecter")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                
                Section {
                    HStack {
                        Text("Statut")
                        Spacer()
                        Text(client.isConnected ? "Connecté" : "Déconnecté")
                            .foregroundColor(client.isConnected ? .green : .red)
                    }
                }
            }
            .navigationTitle("Réglages Trackpad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        // Design moderne iOS
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
