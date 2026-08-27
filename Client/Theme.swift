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

/// Or et argent : la matière réservée aux surfaces payantes.
///
/// Le bleu dit « AirPad », l'or dit « la version payante ». Les confondre ferait
/// passer le paywall pour un écran comme un autre, et c'est précisément l'écran
/// qui doit se distinguer au premier coup d'œil.
enum Premium {
    static let gold = Color(red: 0.85, green: 0.71, blue: 0.42)
    static let silver = Color(red: 0.80, green: 0.82, blue: 0.86)

    /// Un métal ne se rend pas avec un aplat : sans reflet, l'or vire au jaune
    /// moutarde et l'argent au gris souris. Le dégradé reste dans une seule
    /// matière — c'est un éclat, pas une seconde couleur.
    static let goldSheen = LinearGradient(
        colors: [Color(red: 0.97, green: 0.89, blue: 0.68),
                 Color(red: 0.85, green: 0.71, blue: 0.42),
                 Color(red: 0.64, green: 0.48, blue: 0.22)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let silverSheen = LinearGradient(
        colors: [Color(red: 0.94, green: 0.95, blue: 0.97),
                 Color(red: 0.76, green: 0.79, blue: 0.83),
                 Color(red: 0.54, green: 0.57, blue: 0.62)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Le blanc disparaît sur l'or : le texte posé dessus doit être sombre.
    static let onGold = Color(red: 0.13, green: 0.10, blue: 0.04)

    /// Fond des écrans payants : un charbon tiède, pas le bleu nuit du reste
    /// de l'app — l'or posé sur un fond froid devient verdâtre.
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.10, green: 0.09, blue: 0.08),
                 Color(red: 0.07, green: 0.06, blue: 0.05)],
        startPoint: .top, endPoint: .bottom
    )
}

/// Le nom du produit payant, écrit partout de la même façon : « Pro » en or,
/// « AirPad » en argent. Deux écrans qui composent ce lockup à la main finissent
/// toujours par diverger d'un espace ou d'un ton.
struct ProWordmark: View {
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: size * 0.28) {
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.78, weight: .bold))
                .foregroundStyle(Premium.goldSheen)

            // Deux Text séparés plutôt que concaténés : un Text concaténé
            // n'accepte qu'une Color, jamais un dégradé.
            HStack(spacing: 0) {
                Text("AirPad ").foregroundStyle(Premium.silverSheen)
                Text("Pro").foregroundStyle(Premium.goldSheen)
            }
            .font(.system(size: size, weight: .bold, design: .rounded))
        }
    }
}
