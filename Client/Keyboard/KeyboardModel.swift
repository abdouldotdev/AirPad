import SwiftUI

struct MacKey: Identifiable, Equatable {
    let id: String
    let label: String
    let code: UInt16
    var widthMultiplier: CGFloat = 1.0
    var isDark: Bool = false
    var systemImage: String? = nil
    var modifier: Modifier? = nil

    init(label: String, code: UInt16, widthMultiplier: CGFloat = 1.0,
         isDark: Bool = false, systemImage: String? = nil, modifier: Modifier? = nil) {
        // Identité stable : deux touches « ⌘ » distinctes ne doivent pas fusionner
        // dans un ForEach, et un UUID régénéré à chaque rendu casse les animations.
        self.id = "\(label)-\(code)"
        self.label = label
        self.code = code
        self.widthMultiplier = widthMultiplier
        self.isDark = isDark
        self.systemImage = systemImage
        self.modifier = modifier
    }
}

/// Valeurs brutes de `CGEventFlags`, envoyées telles quelles au Mac.
enum Modifier: UInt64, CaseIterable, Identifiable {
    case shift   = 0x00020000
    case control = 0x00040000
    case option  = 0x00080000
    case command = 0x00100000
    case fn      = 0x00800000

    var id: UInt64 { rawValue }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        case .command: return "⌘"
        case .fn: return "fn"
        }
    }
}

/// Modificateurs à bascule.
///
/// L'ancien comportement envoyait `down` au toucher et `up` au relâchement du même
/// doigt : ⌘ était déjà relâché avant que le C ne parte, ce qui rendait ⌘C, ⌘V et
/// ⇧+lettre littéralement impossibles. Un appui arme le modificateur pour la touche
/// suivante ; un double appui le verrouille jusqu'à nouvel ordre.
@MainActor
final class ModifierState: ObservableObject {
    @Published private(set) var armed: Set<Modifier> = []
    @Published private(set) var locked: Set<Modifier> = []

    private var lastTap: [Modifier: Date] = [:]

    func isActive(_ modifier: Modifier) -> Bool {
        armed.contains(modifier) || locked.contains(modifier)
    }

    func isLocked(_ modifier: Modifier) -> Bool { locked.contains(modifier) }

    func toggle(_ modifier: Modifier) {
        let now = Date()
        let isDoubleTap = (lastTap[modifier].map { now.timeIntervalSince($0) < 0.4 }) ?? false
        lastTap[modifier] = now

        if locked.contains(modifier) {
            locked.remove(modifier)
            armed.remove(modifier)
        } else if isDoubleTap {
            locked.insert(modifier)
            armed.remove(modifier)
        } else if armed.contains(modifier) {
            armed.remove(modifier)
        } else {
            armed.insert(modifier)
        }
    }

    /// Masque à joindre à la prochaine touche.
    var flags: UInt64 {
        armed.union(locked).reduce(0) { $0 | $1.rawValue }
    }

    /// Après une touche normale, les modificateurs armés retombent ; les verrouillés restent.
    func consume() {
        guard !armed.isEmpty else { return }
        armed.removeAll()
    }

    func reset() {
        armed.removeAll()
        locked.removeAll()
    }
}

enum KeyboardLayout: String, CaseIterable, Identifiable {
    case qwerty = "QWERTY"
    case azerty = "AZERTY"

    var id: String { rawValue }
}

/// Les codes sont ceux des touches *physiques* d'un clavier Mac (kVK_ANSI_*).
/// Le libellé indique ce que le Mac produit réellement pour la disposition choisie :
/// la touche en position « A » du QWERTY (code 0) tape « Q » sur un Mac en AZERTY.
enum KeyboardLayouts {
    static let functionRow: [MacKey] = [
        MacKey(label: "esc", code: 53, widthMultiplier: 1.5, isDark: true),
        MacKey(label: "F1", code: 122, isDark: true), MacKey(label: "F2", code: 120, isDark: true),
        MacKey(label: "F3", code: 99, isDark: true),  MacKey(label: "F4", code: 118, isDark: true),
        MacKey(label: "F5", code: 96, isDark: true),  MacKey(label: "F6", code: 97, isDark: true),
        MacKey(label: "F7", code: 98, isDark: true),  MacKey(label: "F8", code: 100, isDark: true),
        MacKey(label: "F9", code: 101, isDark: true), MacKey(label: "F10", code: 109, isDark: true),
        MacKey(label: "F11", code: 103, isDark: true), MacKey(label: "F12", code: 111, isDark: true)
    ]

    static let numberRow: [MacKey] = [
        MacKey(label: "1", code: 18), MacKey(label: "2", code: 19), MacKey(label: "3", code: 20),
        MacKey(label: "4", code: 21), MacKey(label: "5", code: 23), MacKey(label: "6", code: 22),
        MacKey(label: "7", code: 26), MacKey(label: "8", code: 28), MacKey(label: "9", code: 25),
        MacKey(label: "0", code: 29)
    ]

    static func topRow(_ layout: KeyboardLayout) -> [MacKey] {
        let labels = layout == .azerty
            ? ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"]
            : ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
        let codes: [UInt16] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35]
        return zip(labels, codes).map { MacKey(label: $0, code: $1) }
    }

    static func homeRow(_ layout: KeyboardLayout) -> [MacKey] {
        let labels = layout == .azerty
            ? ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"]
            : ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";"]
        let codes: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41]
        return zip(labels, codes).map { MacKey(label: $0, code: $1) }
            + [MacKey(label: "⏎", code: 36, widthMultiplier: 2.0, isDark: true)]
    }

    static func bottomRow(_ layout: KeyboardLayout) -> [MacKey] {
        let labels = layout == .azerty
            ? ["W", "X", "C", "V", "B", "N", ",", ";"]
            : ["Z", "X", "C", "V", "B", "N", "M", ","]
        let codes: [UInt16] = [6, 7, 8, 9, 11, 45, 46, 43]
        return [MacKey(label: "⇧", code: 56, widthMultiplier: 1.4, isDark: true, modifier: .shift)]
            + zip(labels, codes).map { MacKey(label: $0, code: $1) }
            + [MacKey(label: "⌫", code: 51, widthMultiplier: 1.6, isDark: true)]
    }

    /// Rangée des modificateurs et de la barre d'espace. Remplace l'ancien `rowSpace`,
    /// qui n'était jamais affiché, et l'ancienne barre d'espace au libellé vide.
    static let modifierRow: [MacKey] = [
        MacKey(label: "fn", code: 63, isDark: true, modifier: .fn),
        MacKey(label: "⌃", code: 59, isDark: true, modifier: .control),
        MacKey(label: "⌥", code: 58, isDark: true, modifier: .option),
        MacKey(label: "⌘", code: 55, widthMultiplier: 1.3, isDark: true, modifier: .command),
        MacKey(label: "space", code: 49, widthMultiplier: 4.2),
        MacKey(label: "◀", code: 123, isDark: true),
        MacKey(label: "▼", code: 125, isDark: true),
        MacKey(label: "▲", code: 126, isDark: true),
        MacKey(label: "▶", code: 124, isDark: true)
    ]
}
