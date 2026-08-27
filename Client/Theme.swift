import SwiftUI

/// L'accent unique de l'app.
///
/// Les dégradés bleu → violet du premier jet donnaient à chaque écran payant sa
/// propre couleur ; l'ensemble se lisait comme trois produits différents. Un seul
/// ton, décliné en opacités, tient la cohérence sans effort.
enum Brand {
    static let accent = Color(red: 0.25, green: 0.55, blue: 1.0)

    /// Fond des surfaces qui doivent rappeler l'accent sans le crier.
    static let accentWash = Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.14)
}

/// Le nom du produit payant, écrit partout de la même façon : « Pro » porte
/// l'accent et la couronne, « AirPad » reste neutre. Deux écrans qui composent
/// ce lockup à la main finissent toujours par diverger d'un espace ou d'un ton.
struct ProWordmark: View {
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: size * 0.24) {
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(Brand.accent)

            (Text("AirPad ").foregroundColor(.white)
             + Text("Pro").foregroundColor(Brand.accent))
                .font(.system(size: size, weight: .bold, design: .rounded))
        }
    }
}
