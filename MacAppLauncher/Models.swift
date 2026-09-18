import AppKit
import Foundation

struct Hotkey: Equatable {
    var keyCode: Int
    var modifiers: Int

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    }

    var displayString: String {
        if keyCode < 0 {
            return "Record Hotkey"
        }
        var parts: [String] = []
        if modifierFlags.contains(.control) {
            parts.append("⌃")
        }
        if modifierFlags.contains(.option) {
            parts.append("⌥")
        }
        if modifierFlags.contains(.shift) {
            parts.append("⇧")
        }
        if modifierFlags.contains(.command) {
            parts.append("⌘")
        }
        let key = KeyCodeMapper.displayName(for: keyCode)
        return parts.joined() + key
    }

    static let unset = Hotkey(keyCode: -1, modifiers: 0)
}

struct AppEntry: Identifiable, Equatable {
    let id: Int
    let bundleId: String
    let name: String
    let path: String
    let bookmarkData: Data?
    let hotkey: Hotkey
    let launchCount: Int
    let lastLaunchedAt: Date?

    var requiresAuthorization: Bool {
        bookmarkData == nil
    }
}

struct SceneEntry: Identifiable, Equatable {
    let id: Int
    let name: String
    let hotkey: Hotkey
    let appIDs: [Int]
    let resources: [SceneResource]
}

struct SceneResource: Identifiable, Equatable {
    enum Kind: String {
        case website
        case file
    }

    let id: Int
    let kind: Kind
    let value: String
    let bookmarkData: Data?

    var title: String {
        kind == .file ? URL(fileURLWithPath: value).lastPathComponent : value
    }

    static func validatedWebsite(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url.absoluteString
    }
}

enum LaunchResult: Equatable {
    case launched(refreshedBookmark: Data?, resolvedPath: String?)
    case hidden
}

struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

enum KeyCodeMapper {
    private static let mapping: [Int: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        25: "9",
        26: "7",
        28: "8",
        29: "0",
        31: "O",
        32: "U",
        34: "I",
        35: "P",
        37: "L",
        38: "J",
        40: "K",
        45: "N",
        46: "M",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        118: "F4",
        120: "F2",
        122: "F1"
    ]

    static func displayName(for keyCode: Int) -> String {
        if let name = mapping[keyCode] {
            return name
        }
        return "Key\(keyCode)"
    }

    static func isFunctionKey(_ keyCode: Int) -> Bool {
        [96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122].contains(keyCode)
    }
}
