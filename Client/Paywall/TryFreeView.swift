import SwiftUI

/// La page d'accueil de qui n'a pas d'abonnement.
///
/// Elle remplace l'écran de contrôle au lieu de se poser dessus : un panneau
/// flottant au-dessus d'un trackpad flouté demandait à l'œil de choisir entre
/// deux surfaces, et donnait l'impression d'un produit qu'on retient en otage.
/// Ici il n'y a qu'une page, une promesse, un geste.
struct TryFreeView: View {
    var onTry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteControlHero()
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()

            Spacer(minLength: 12)

            Text(T("We want you to use AirPad for free.",
                   "On veut que vous utilisiez AirPad gratuitement."))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            Button(action: onTry) {
                Text(T("Try it now", "Essayer maintenant"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Premium.goldSheen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(Premium.onGold)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)

            Spacer(minLength: 20)
        }
    }
}

/// Le geste fait sur le téléphone arrive sur le Mac.
///
/// C'est tout ce que vend le produit, et une capture figée ne le montre pas :
/// il faut voir le curseur partir du doigt. La scène est inclinée et déborde du
/// cadre pour qu'on la lise comme un objet posé là, pas comme un schéma.
private struct RemoteControlHero: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Aller-retour adouci : un déplacement linéaire se lit comme une
            // machine, pas comme une main.
            let raw = (sin(t * 0.9) + 1) / 2
            let p = raw * raw * (3 - 2 * raw)

            ZStack {
                halo

                macScreen(progress: p)
                    .frame(width: 300, height: 200)
                    .rotation3DEffect(.degrees(16), axis: (x: 1, y: -0.5, z: 0), perspective: 0.55)
                    .rotationEffect(.degrees(-7))
                    .offset(x: 62, y: -34)

                link(progress: p)

                phone(progress: p)
                    .frame(width: 120, height: 224)
                    .rotation3DEffect(.degrees(14), axis: (x: 0.35, y: 1, z: 0), perspective: 0.55)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -96, y: 76)
            }
        }
    }

    private var halo: some View {
        RadialGradient(colors: [Premium.gold.opacity(0.20), .clear],
                       center: .center, startRadius: 8, endRadius: 210)
            .blur(radius: 22)
    }

    private func macScreen(progress p: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Premium.silver.opacity(0.28), lineWidth: 1.4)
                )

            // Le texte qui s'écrit : des barres de largeurs inégales se lisent
            // comme des mots, des barres égales comme une jauge.
            let typed = Int(p * 6)
            HStack(spacing: 4) {
                ForEach(0..<max(typed, 0), id: \.self) { i in
                    Capsule()
                        .fill(Premium.silver.opacity(0.55))
                        .frame(width: [16, 10, 22, 13, 9, 18][i % 6], height: 5)
                }
                Capsule().fill(Premium.gold).frame(width: 2, height: 13)
            }
            .padding(.leading, 26)
            .padding(.top, 34)

            Image(systemName: "cursorarrow.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                .offset(x: 44 + p * 168, y: 118 - p * 62)
        }
    }

    private func phone(progress p: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Premium.gold.opacity(0.45), lineWidth: 1.4)
                )

            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(white: 0.86))
                .padding(10)

            // Le doigt. Le halo qui l'entoure fait la différence entre « un
            // point » et « quelque chose qu'on touche ».
            Circle()
                .fill(Premium.gold)
                .frame(width: 22, height: 22)
                .overlay(Circle().fill(Premium.gold.opacity(0.28)).frame(width: 46, height: 46))
                .offset(x: -26 + p * 52, y: 44 - p * 30)
        }
    }

    /// Le trait qui relie les deux, et la bille qui le parcourt : sans elle, on
    /// voit deux appareils côte à côte, pas l'un qui commande l'autre.
    private func link(progress p: Double) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 78, y: 232))
                path.addQuadCurve(to: CGPoint(x: 232, y: 96),
                                  control: CGPoint(x: 108, y: 108))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [4, 6]))
            .foregroundStyle(Premium.gold.opacity(0.35))

            Circle()
                .fill(Premium.gold)
                .frame(width: 7, height: 7)
                .shadow(color: Premium.gold.opacity(0.8), radius: 6)
                .offset(x: -78 + p * 154, y: 76 - p * 136)
        }
        .frame(width: 310, height: 310)
    }
}
