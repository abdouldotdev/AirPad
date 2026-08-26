import SwiftUI
import AVFoundation
import AudioToolbox

enum CameraPermission {
    case unknown, granted, denied
}

/// Vue dont la couche *est* l'aperçu caméra : le cadrage suit automatiquement la
/// taille réelle de la vue. L'ancien code figeait la couche à `UIScreen.main.bounds`
/// alors que la zone ne fait que 180 pt de haut, d'où un aperçu déformé et rogné.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct QRCodeScannerView: UIViewRepresentable {
    var isPaused: Bool = false
    var onPermissionChange: (CameraPermission) -> Void
    var onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setPaused(isPaused)
    }

    /// Sans cet arrêt explicite, la caméra continuait de tourner après la fermeture
    /// de la feuille : voyant allumé et batterie consommée pour rien.
    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRCodeScannerView
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "dev.abdouldotdev.airpad.camera")
        private var isConfigured = false
        private var didFind = false

        init(parent: QRCodeScannerView) {
            self.parent = parent
        }

        func attach(to view: CameraPreviewView) {
            view.previewLayer.session = session
            requestAccess(for: view)
        }

        private func requestAccess(for view: CameraPreviewView) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                report(.granted)
                configureAndStart()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.report(granted ? .granted : .denied)
                        if granted { self?.configureAndStart() }
                    }
                }
            default:
                // Refus explicite : l'app doit le dire et proposer les Réglages,
                // au lieu d'afficher un rectangle noir sans explication.
                report(.denied)
            }
        }

        private func report(_ permission: CameraPermission) {
            DispatchQueue.main.async { self.parent.onPermissionChange(permission) }
        }

        private func configureAndStart() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.isConfigured {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }

                    guard let device = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: device),
                          self.session.canAddInput(input) else { return }
                    self.session.addInput(input)

                    let output = AVCaptureMetadataOutput()
                    guard self.session.canAddOutput(output) else { return }
                    self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.qr]
                    self.isConfigured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }

        func setPaused(_ paused: Bool) {
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured else { return }
                if paused, self.session.isRunning { self.session.stopRunning() }
                else if !paused, !self.session.isRunning { self.session.startRunning() }
            }
        }

        func stop() {
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didFind,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            didFind = true
            AudioServicesPlaySystemSound(1057)
            parent.onFound(value)
            stop()
        }
    }
}
