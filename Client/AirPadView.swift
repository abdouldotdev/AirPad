import SwiftUI
import Network
import UIKit
import AVFoundation

// --- LOCALIZATION HELPER ---
func T(_ en: String, _ fr: String) -> String {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    return lang.hasPrefix("fr") ? fr : en
}

class NetworkClient: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "UDP Client Queue", qos: .userInteractive)
    
    @Published var isConnected: Bool = false
    
    func connect(to ipAddress: String, port: NWEndpoint.Port = 8080) {
        let host = NWEndpoint.Host(ipAddress)
        connection = NWConnection(host: host, port: port, using: .udp)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.isConnected = (state == .ready)
                if state == .ready { self?.send("INIT:\(UIDevice.current.name)") }
            }
        }
        connection?.start(queue: queue)
    }
    
    func sendMove(dx: CGFloat, dy: CGFloat) { send("M:\(dx):\(dy)") }
    func sendScroll(dx: CGFloat, dy: CGFloat) { send("S:\(dx):\(dy)") }
    func sendClick() { send("C:1") }
    func sendRightClick() { send("R:1") }
    func sendKey(code: UInt16, isDown: Bool) { send("K:\(code):\(isDown ? 1 : 0)") }
    
    private func send(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }
}

struct MacKey: Identifiable {
    let id = UUID()
    let label: String
    let code: UInt16
    var widthMultiplier: CGFloat = 1.0
    var isDark: Bool = false
}

struct AirPadView: View {
    @StateObject private var client = NetworkClient()
    @AppStorage("serverIP") private var serverIP: String = "192.168.1.50"
    @AppStorage("advancedMode") private var advancedMode = false
    @State private var showSettings = false
    
    let rowFn = [
        MacKey(label: "esc", code: 53, widthMultiplier: 1.5, isDark: true),
        MacKey(label: "F1", code: 122, isDark: true), MacKey(label: "F2", code: 120, isDark: true),
        MacKey(label: "F3", code: 99, isDark: true), MacKey(label: "F4", code: 118, isDark: true),
        MacKey(label: "F5", code: 96, isDark: true), MacKey(label: "F6", code: 97, isDark: true),
        MacKey(label: "F7", code: 98, isDark: true), MacKey(label: "F8", code: 100, isDark: true),
        MacKey(label: "F9", code: 101, isDark: true), MacKey(label: "F10", code: 109, isDark: true),
        MacKey(label: "F11", code: 103, isDark: true), MacKey(label: "F12", code: 111, isDark: true)
    ]
    let rowNum = [
        MacKey(label: "1", code: 18), MacKey(label: "2", code: 19), MacKey(label: "3", code: 20), MacKey(label: "4", code: 21), MacKey(label: "5", code: 23),
        MacKey(label: "6", code: 22), MacKey(label: "7", code: 26), MacKey(label: "8", code: 28), MacKey(label: "9", code: 25), MacKey(label: "0", code: 29)
    ]
    let row1 = [
        MacKey(label: "Q", code: 12), MacKey(label: "W", code: 13), MacKey(label: "E", code: 14), MacKey(label: "R", code: 15), MacKey(label: "T", code: 17),
        MacKey(label: "Y", code: 16), MacKey(label: "U", code: 32), MacKey(label: "I", code: 34), MacKey(label: "O", code: 31), MacKey(label: "P", code: 35)
    ]
    let row2 = [
        MacKey(label: "A", code: 0), MacKey(label: "S", code: 1), MacKey(label: "D", code: 2), MacKey(label: "F", code: 3), MacKey(label: "G", code: 5),
        MacKey(label: "H", code: 4), MacKey(label: "J", code: 38), MacKey(label: "K", code: 40), MacKey(label: "L", code: 37), MacKey(label: "⏎", code: 36, widthMultiplier: 1.5, isDark: true)
    ]
    let row3 = [
        MacKey(label: "⇧", code: 56, widthMultiplier: 1.2, isDark: true), MacKey(label: "Z", code: 6), MacKey(label: "X", code: 7), MacKey(label: "C", code: 8), MacKey(label: "V", code: 9),
        MacKey(label: "B", code: 11), MacKey(label: "N", code: 45), MacKey(label: "M", code: 46), MacKey(label: "⌫", code: 51, widthMultiplier: 1.5, isDark: true)
    ]
    let row4 = [
        MacKey(label: "fn", code: 63, isDark: true), MacKey(label: "⌃", code: 59, isDark: true), MacKey(label: "⌥", code: 58, isDark: true), MacKey(label: "⌘", code: 55, widthMultiplier: 1.2, isDark: true),
        MacKey(label: "", code: 49, widthMultiplier: 4.0),
        MacKey(label: "⌘", code: 54, widthMultiplier: 1.2, isDark: true), MacKey(label: "⌥", code: 61, isDark: true)
    ]
    
    var trackpadZone: some View {
        ZStack {
            TrackpadUIKitView(client: client)
                .ignoresSafeArea(.all, edges: .top)
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
    }
    
    var keyboardZone: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - 16
            let baseKeyWidth = max(0, (availableWidth - (9 * 6)) / 10)
            
            ZStack {
                Color(white: 0.18)
                VStack(spacing: 8) {
                    if advancedMode {
                        KeyboardRow(keys: rowFn, client: client).frame(height: baseKeyWidth * 0.8)
                    }
                    KeyboardRow(keys: rowNum, client: client).frame(height: baseKeyWidth)
                    KeyboardRow(keys: row1, client: client).frame(height: baseKeyWidth)
                    KeyboardRow(keys: row2, client: client).frame(height: baseKeyWidth)
                    KeyboardRow(keys: row3, client: client).frame(height: baseKeyWidth)
                    KeyboardRow(keys: row4, client: client).frame(height: baseKeyWidth)
                }
                .padding(8)
            }
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        trackpadZone.frame(width: geo.size.width * 0.45)
                        keyboardZone.frame(width: geo.size.width * 0.55)
                    }
                } else {
                    VStack(spacing: 0) {
                        trackpadZone.frame(height: geo.size.height * 0.45)
                        keyboardZone.frame(height: geo.size.height * 0.55)
                    }
                }
            }
        }
        .background(Color(white: 0.12).edgesIgnoringSafeArea(.all))
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client, serverIP: $serverIP)
        }
        .onAppear { client.connect(to: serverIP) }
    }
}

struct TrackpadUIKitView: UIViewRepresentable {
    let client: NetworkClient
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scroll)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tap)
        
        let rightTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightTap(_:)))
        rightTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(rightTap)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(client: client) }
    
    class Coordinator: NSObject {
        let client: NetworkClient
        var lastPanPoint: CGPoint?
        var lastScrollPoint: CGPoint?
        
        init(client: NetworkClient) { self.client = client }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            if gesture.state == .began { lastPanPoint = point }
            else if gesture.state == .changed, let last = lastPanPoint {
                client.sendMove(dx: point.x - last.x, dy: point.y - last.y)
                lastPanPoint = point
            }
            else if gesture.state == .ended { lastPanPoint = nil }
        }
        
        @objc func handleScroll(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            if gesture.state == .began { lastScrollPoint = point }
            else if gesture.state == .changed, let last = lastScrollPoint {
                client.sendScroll(dx: point.x - last.x, dy: point.y - last.y)
                lastScrollPoint = point
            }
            else if gesture.state == .ended { lastScrollPoint = nil }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            client.sendClick()
        }
        
        @objc func handleRightTap(_ gesture: UITapGestureRecognizer) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.sendRightClick()
        }
    }
}

struct KeyboardRow: View {
    let keys: [MacKey]
    let client: NetworkClient
    let totalMultiplier: CGFloat
    
    init(keys: [MacKey], client: NetworkClient) {
        self.keys = keys
        self.client = client
        self.totalMultiplier = keys.reduce(0) { $0 + $1.widthMultiplier }
    }
    
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let availableWidth = geo.size.width - (CGFloat(keys.count - 1) * spacing)
            
            HStack(spacing: spacing) {
                ForEach(keys) { key in
                    PhysicalKeyView(key: key, client: client)
                        .frame(width: max(0, availableWidth * (key.widthMultiplier / totalMultiplier)))
                }
            }
        }
    }
}

struct PhysicalKeyView: View {
    let key: MacKey
    let client: NetworkClient
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.6))
                .offset(y: isPressed ? 1 : 3)
            
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        key.isDark ? Color(white: 0.2) : Color(white: 0.35),
                        key.isDark ? Color(white: 0.15) : Color(white: 0.28)
                    ]),
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .offset(y: isPressed ? 2 : 0)
            
            Text(key.label)
                .font(.system(size: key.label.count > 1 ? 14 : 18, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .offset(y: isPressed ? 2 : 0)
        }
        .frame(maxHeight: .infinity)
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
}

// --- QR SCANNER ---
struct QRCodeScannerView: UIViewControllerRepresentable {
    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRCodeScannerView
        var didFindCode: Bool = false
        
        init(parent: QRCodeScannerView) { self.parent = parent }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didFindCode else { return }
            
            if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let stringValue = metadataObject.stringValue {
                // Ensure we only process IP addresses (rudimentary check)
                if stringValue.contains(".") {
                    didFindCode = true
                    DispatchQueue.main.async {
                        self.parent.didFindCode(stringValue)
                    }
                }
            }
        }
    }
    
    var didFindCode: (String) -> Void
    
    func makeCoordinator() -> Coordinator { return Coordinator(parent: self) }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        let session = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return viewController }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return viewController }
        
        if (session.canAddInput(videoInput)) { session.addInput(videoInput) } else { return viewController }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if (session.canAddOutput(metadataOutput)) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else { return viewController }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = UIScreen.main.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct SettingsView: View {
    @ObservedObject var client: NetworkClient
    @Binding var serverIP: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Scan Mac QR Code", "Scanner le QR Code du Mac"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    QRCodeScannerView { scannedIP in
                        serverIP = scannedIP
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        client.connect(to: serverIP)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .frame(height: 180)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Manual Entry", "Saisie Manuelle de l'IP"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField(T("e.g. 192.168.1.50", "ex: 192.168.1.50"), text: $serverIP)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(height: 44)
                        
                        Button(action: {
                            client.connect(to: serverIP)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text(T("Connect", "Connecter"))
                                .bold()
                                .frame(height: 44)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Preferences", "Préférences"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Toggle(T("Advanced Mode (F1-F12 Keys)", "Mode Avancé (Touches F1-F12)"), isOn: AppStorage(wrappedValue: false, "advancedMode"))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(24)
            .navigationTitle(T("AirPad Settings", "Réglages AirPad"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(T("Close", "Fermer")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.65), .large])
    }
}
