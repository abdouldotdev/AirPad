import SwiftUI
import UIKit

struct TrackpadUIKitView: UIViewRepresentable {
    let client: NetworkClient
    var trackingSpeed: Double
    var allowsAdvancedGestures: Bool
    var onGesture: (String) -> Void
    var onPremiumGesture: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let scroll = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scroll)

        // Gestes à 3 doigts : réservés à l'abonnement, mais toujours détectés pour
        // pouvoir proposer l'offre au lieu de rester silencieux.
        let swipe = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleAdvancedSwipe(_:)))
        swipe.minimumNumberOfTouches = 3
        swipe.maximumNumberOfTouches = 4
        view.addGestureRecognizer(swipe)

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tap)

        let rightTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleRightTap(_:)))
        rightTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(rightTap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.trackingSpeed = trackingSpeed
        context.coordinator.allowsAdvancedGestures = allowsAdvancedGestures
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(client: client, trackingSpeed: trackingSpeed,
                    allowsAdvancedGestures: allowsAdvancedGestures,
                    onGesture: onGesture, onPremiumGesture: onPremiumGesture)
    }

    /// Les reconnaissances de gestes UIKit sont livrées sur le thread principal :
    /// l'isolation explicite évite d'avoir à sauter d'acteur à chaque déplacement.
    @MainActor
    final class Coordinator: NSObject {
        let client: NetworkClient
        var trackingSpeed: Double
        var allowsAdvancedGestures: Bool
        let onGesture: (String) -> Void
        let onPremiumGesture: () -> Void

        private var lastPanPoint: CGPoint?
        private var lastScrollPoint: CGPoint?
        private var didHandleSwipe = false

        init(client: NetworkClient, trackingSpeed: Double, allowsAdvancedGestures: Bool,
             onGesture: @escaping (String) -> Void, onPremiumGesture: @escaping () -> Void) {
            self.client = client
            self.trackingSpeed = trackingSpeed
            self.allowsAdvancedGestures = allowsAdvancedGestures
            self.onGesture = onGesture
            self.onPremiumGesture = onPremiumGesture
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                lastPanPoint = point
            case .changed:
                guard let last = lastPanPoint else { return }
                client.sendMove(dx: (point.x - last.x) * trackingSpeed,
                                dy: (point.y - last.y) * trackingSpeed)
                lastPanPoint = point
            default:
                lastPanPoint = nil
            }
        }

        @objc func handleScroll(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                lastScrollPoint = point
                onGesture("two_finger_scroll")
            case .changed:
                guard let last = lastScrollPoint else { return }
                client.sendScroll(dx: point.x - last.x, dy: point.y - last.y)
                lastScrollPoint = point
            default:
                lastScrollPoint = nil
            }
        }

        @objc func handleAdvancedSwipe(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                didHandleSwipe = false
            case .changed:
                guard !didHandleSwipe else { return }
                let translation = gesture.translation(in: gesture.view)
                guard max(abs(translation.x), abs(translation.y)) > 60 else { return }
                didHandleSwipe = true

                guard allowsAdvancedGestures else {
                    onPremiumGesture()
                    return
                }
                let fingers = gesture.numberOfTouches
                if abs(translation.x) > abs(translation.y) {
                    // ⌃← / ⌃→ : changer de bureau.
                    let code: UInt16 = translation.x < 0 ? 124 : 123
                    client.sendKey(code: code, isDown: true, flags: Modifier.control.rawValue)
                    client.sendKey(code: code, isDown: false, flags: Modifier.control.rawValue)
                    onGesture("\(fingers)_finger_swipe_horizontal")
                } else {
                    // ⌃↑ : Mission Control, ⌃↓ : fenêtres de l'app.
                    let code: UInt16 = translation.y < 0 ? 126 : 125
                    client.sendKey(code: code, isDown: true, flags: Modifier.control.rawValue)
                    client.sendKey(code: code, isDown: false, flags: Modifier.control.rawValue)
                    onGesture("\(fingers)_finger_swipe_vertical")
                }
            default:
                didHandleSwipe = false
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            client.sendClick()
            onGesture("tap_click")
        }

        @objc func handleRightTap(_ gesture: UITapGestureRecognizer) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.sendRightClick()
            onGesture("two_finger_click")
        }
    }
}
