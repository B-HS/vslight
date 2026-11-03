import AppKit
import Carbon

struct Hotkey: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    var isValid: Bool {
        modifiers != 0
    }

    var modifierSymbols: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 {
            symbols += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            symbols += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            symbols += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            symbols += "⌘"
        }
        return symbols
    }

    var displayString: String {
        modifierSymbols + KeyCodeNames.label(for: keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }
}

enum KeyCodeNames {
    static func label(for keyCode: UInt32) -> String {
        labels[keyCode] ?? "키 \(keyCode)"
    }

    private static let labels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]
}
