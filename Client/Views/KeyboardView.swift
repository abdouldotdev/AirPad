import SwiftUI

struct KeyboardRow: View {
    let keys: [MacKey]
    let client: NetworkClient
    @ObservedObject var modifiers: ModifierState

    private var totalMultiplier: CGFloat {
        keys.reduce(0) { $0 + $1.widthMultiplier }
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let available = max(0, geo.size.width - (CGFloat(keys.count - 1) * spacing))
            HStack(spacing: spacing) {
                ForEach(keys) { key in
                    PhysicalKeyView(key: key, client: client, modifiers: modifiers)
                        .frame(width: available * (key.widthMultiplier / totalMultiplier))
                }
            }
        }
    }
}

struct PhysicalKeyView: View {
    let key: MacKey
    let client: NetworkClient
    @ObservedObject var modifiers: ModifierState

    @State private var isPressed = false

    private var isModifierActive: Bool {
        guard let modifier = key.modifier else { return false }
        return modifiers.isActive(modifier)
    }

    private var isModifierLocked: Bool {
        guard let modifier = key.modifier else { return false }
        return modifiers.isLocked(modifier)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .offset(y: isPressed ? 1 : 4)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(surfaceColor)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [.white.opacity(key.isDark ? 0.1 : 0.3), .clear, .black.opacity(0.3)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                )
                .offset(y: isPressed ? 3 : 0)

            VStack(spacing: 2) {
                Text(key.label)
                    .font(.system(size: key.label.count > 1 ? 13 : 18, weight: .medium))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                // Un modificateur verrouillé doit se distinguer d'un modificateur
                // simplement armé, sinon on ne sait plus dans quel état on tape.
                if isModifierLocked {
                    Capsule().fill(Color.white).frame(width: 12, height: 2)
                }
            }
            .foregroundColor(isModifierActive ? .black : .white.opacity(0.9))
            .offset(y: isPressed ? 3 : 0)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isModifierActive ? [.isSelected, .isButton] : .isButton)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    if key.modifier == nil { press() }
                }
                .onEnded { _ in
                    isPressed = false
                    if let modifier = key.modifier {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        modifiers.toggle(modifier)
                    } else {
                        client.sendKey(code: key.code, isDown: false, flags: modifiers.flags)
                        modifiers.consume()
                    }
                }
        )
    }

    private func press() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        client.sendKey(code: key.code, isDown: true, flags: modifiers.flags)
    }

    private var surfaceColor: Color {
        if isModifierActive { return Color.white.opacity(0.85) }
        return key.isDark ? Color.black.opacity(0.2) : Color.white.opacity(0.1)
    }

    private var accessibilityLabel: String {
        guard let modifier = key.modifier else { return key.label }
        let state = isModifierLocked
            ? T("locked", "verrouillé")
            : (isModifierActive ? T("on", "activé") : T("off", "désactivé"))
        return "\(modifier.symbol), \(state)"
    }
}
