import AppKit
import Carbon

struct ShelfShortcut {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = ShelfShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey))

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var displayName: String {
        var name = ""
        if modifiers & UInt32(controlKey) != 0 { name += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { name += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { name += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { name += "⌘" }
        return name + ShelfShortcut.keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete", UInt32(kVK_Escape): "Esc"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

/// Keeps a single press active until any member of the shortcut is released.
/// The timer also runs during AppKit drag/menu tracking, when Carbon delivery
/// may be delayed. Only this shortcut's current state is sampled, while held.
final class HoldGesture {
    struct Keys {
        var command: Bool
        var shift: Bool
        var s: Bool
        var allDown: Bool { command && shift && s }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private(set) var isPressed = false
    private var timer: Timer?
    private var readKeys: () -> Keys

    init(readKeys: @escaping () -> Keys = {
        let flags = NSEvent.modifierFlags
        return Keys(command: flags.contains(.command), shift: flags.contains(.shift),
                    s: CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_S)))
    }) {
        self.readKeys = readKeys
    }

    func configure(for shortcut: ShelfShortcut) {
        readKeys = {
            let flags = NSEvent.modifierFlags
            return Keys(command: shortcut.modifierFlags.contains(.command) ? flags.contains(.command) : true,
                        shift: shortcut.modifierFlags.contains(.shift) ? flags.contains(.shift) : true,
                        s: CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode)))
        }
    }

    func press() {
        guard !isPressed else { return } // Ignore repeated key-down events.
        isPressed = true
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.checkForRelease() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        onPress?()
    }

    func release() {
        guard isPressed else { return }
        isPressed = false
        timer?.invalidate()
        timer = nil
        onRelease?()
    }

    func checkForRelease() {
        if isPressed && !readKeys().allDown { release() }
    }

    deinit { timer?.invalidate() }
}
