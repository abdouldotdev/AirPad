import Foundation

/// Un Mac appairé : adresse, port et code d'appairage validé par le serveur.
struct PairedMac: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: UInt16
    var token: String

    /// Analytics : identifie un Mac de façon stable sans jamais transmettre son IP.
    var anonymousID: String { id.uuidString }
}

/// Décode la charge utile du QR : `airpad://pair?h=<ip>&p=<port>&t=<token>`.
enum PairingPayload {
    static func parse(_ raw: String) -> PairedMac? {
        guard let components = URLComponents(string: raw),
              components.scheme == "airpad",
              components.host == "pair" else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        guard let host = value("h"), isValidIPv4(host),
              let token = value("t"), token.count == 8 else { return nil }

        let port = UInt16(value("p") ?? "") ?? 8080
        return PairedMac(name: value("n") ?? "Mac", host: host, port: port, token: token)
    }

    static func isValidIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part), part.count <= 3, !part.isEmpty else { return false }
            return (0...255).contains(n)
        }
    }

    /// Nettoie un code saisi à la main : « a3f9-k2m7 » et « A3F9 K2M7 » sont acceptés.
    static func normalizeCode(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Liste des Macs appairés. Le multi-Mac est réservé à l'abonnement ; en gratuit,
/// seul le dernier Mac appairé est conservé.
@MainActor
final class PairedMacStore: ObservableObject {
    private static let key = "pairedMacs"

    @Published private(set) var macs: [PairedMac] = []
    @Published var selectedID: UUID?

    var selected: PairedMac? {
        macs.first(where: { $0.id == selectedID }) ?? macs.first
    }

    init() {
        load()
        selectedID = macs.first?.id
    }

    func upsert(_ mac: PairedMac, allowMultiple: Bool) {
        if let index = macs.firstIndex(where: { $0.host == mac.host }) {
            macs[index].token = mac.token
            macs[index].port = mac.port
            selectedID = macs[index].id
        } else {
            if !allowMultiple { macs.removeAll() }
            macs.append(mac)
            selectedID = mac.id
        }
        save()
    }

    func remove(_ mac: PairedMac) {
        macs.removeAll { $0.id == mac.id }
        if selectedID == mac.id { selectedID = macs.first?.id }
        save()
    }

    /// Appelé quand l'abonnement expire : on retombe à un seul Mac.
    func trimToFreeTier() {
        guard macs.count > 1 else { return }
        let keep = selected ?? macs[0]
        macs = [keep]
        selectedID = keep.id
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([PairedMac].self, from: data) else { return }
        macs = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(macs) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
