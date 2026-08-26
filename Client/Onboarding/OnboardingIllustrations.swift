import SwiftUI

/// Illustrations dessinées en SwiftUI plutôt qu'importées : elles s'adaptent à toutes
/// les tailles d'écran, suivent le thème et ne pèsent rien dans le bundle.

/// Écran 1 — le problème : le Mac est de l'autre côté de la pièce.
struct DistanceIllustration: View {
    @State private var nudge = false

    var body: some View {
        HStack(spacing: 0) {
            PhoneShape()
                .frame(width: 54, height: 96)

            ZStack {
                // La distance qui sépare l'utilisateur de son Mac.
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 2)
                    .mask(
                        HStack(spacing: 6) {
                            ForEach(0..<14, id: \.self) { _ in
                                Capsule().frame(width: 10)
                            }
                        }
                    )

                Image(systemName: "figure.walk")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .offset(x: nudge ? 26 : -26)
            }
            .frame(maxWidth: .infinity)

            MacShape(isDim: true)
                .frame(width: 128, height: 92)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { nudge = true }
        }
    }
}

/// Écran 2 — la solution : le doigt sur le téléphone déplace le curseur du Mac.
struct ControlIllustration: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                PhoneShape(isActive: true)
                    .frame(width: 74, height: 132)
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .blur(radius: 0.4)
                    .offset(x: -14 + progress * 28, y: 24 - progress * 34)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            ZStack(alignment: .topLeading) {
                MacShape()
                    .frame(width: 158, height: 112)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: 34 + progress * 74, y: 66 - progress * 44)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { progress = 1 }
        }
    }
}

/// Écran 3 — l'appairage : un code affiché sur le Mac, scanné par le téléphone.
struct PairingIllustration: View {
    @State private var sweep: CGFloat = 0

    var body: some View {
        ZStack {
            MacShape()
                .frame(width: 190, height: 134)

            RoundedRectangle(cornerRadius: 8)
                .fill(.white)
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: "qrcode")
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .foregroundStyle(.black)
                )
                .offset(y: -8)
                .overlay(
                    // Le trait de scan indique sans mot que le téléphone lit le code.
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .green, .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 58, height: 22)
                        .offset(y: -8 + sweep)
                        .blendMode(.plusLighter)
                )
                .mask(RoundedRectangle(cornerRadius: 8).frame(width: 58, height: 58).offset(y: -8))
        }
        .onAppear {
            sweep = -26
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweep = 26 }
        }
    }
}

// MARK: - Formes de base

struct PhoneShape: View {
    var isActive = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(white: 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? Color.blue.opacity(0.8) : Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive
                          ? LinearGradient(colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.12)],
                                           startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .padding(5)
            )
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }
}

struct MacShape: View {
    var isDim = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(isDim ? 0.12 : 0.22), lineWidth: 1.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(isDim ? 0.03 : 0.08))
                        .padding(6)
                )
            // Le socle : sans lui la forme se lit comme une simple boîte.
            Capsule()
                .fill(Color(white: 0.28))
                .frame(height: 5)
                .padding(.horizontal, 22)
        }
        .opacity(isDim ? 0.55 : 1)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
    }
}
