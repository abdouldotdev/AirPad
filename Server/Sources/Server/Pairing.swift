import Foundation

/// Code d'appairage partagé entre le Mac et le téléphone.
///
/// Sans lui, n'importe qui sur le même Wi-Fi (café, coworking, hôtel) peut ouvrir une
/// connexion sur le port et piloter la souris et le clavier du Mac. Le code est encodé
/// dans le QR ; la saisie manuelle en affiche une version lisible à recopier.
@MainActor
final class PairingManager: ObservableObject {
    private static let storageKey = "pairingToken"

    @Published private(set) var token: String

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.storageKey), saved.count == 8 {
            token = saved
        } else {
            token = Self.makeToken()
            UserDefaults.standard.set(token, forKey: Self.storageKey)
        }
    }

    /// Révoque l'accès de tous les appareils déjà appairés.
    func regenerate() {
        token = Self.makeToken()
        UserDefaults.standard.set(token, forKey: Self.storageKey)
    }

    func isValid(_ candidate: String) -> Bool {
        // Comparaison à durée constante : sur un réseau local, un attaquant peut
        // mesurer le temps de réponse pour deviner le code caractère par caractère.
        let a = Array(candidate.uppercased().utf8)
        let b = Array(token.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<b.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    /// Charge utile du QR code.
    func pairingPayload(host: String, port: UInt16) -> String {
        "airpad://pair?h=\(host)&p=\(port)&t=\(token)"
    }

    /// Code affiché à l'écran, groupé pour être recopié sans erreur : « A3F9-K2M7 ».
    var displayCode: String {
        let middle = token.index(token.startIndex, offsetBy: 4)
        return "\(token[token.startIndex..<middle])-\(token[middle...])"
    }

    /// Alphabet sans I, O, 0, 1 : ces caractères se confondent quand on recopie un code.
    private static func makeToken() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}
