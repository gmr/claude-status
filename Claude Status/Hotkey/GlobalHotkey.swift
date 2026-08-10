import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut: a virtual key code plus Carbon modifier flags.
nonisolated struct GlobalHotkey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Builds a hotkey from a key-down event. Requires at least one non-shift
    /// modifier so plain typing can't be registered as a global shortcut.
    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers & ~UInt32(shiftKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    // MARK: - Persistence

    private static let keyCodeKey = "globalHotkeyKeyCode"
    private static let modifiersKey = "globalHotkeyModifiers"

    /// The user-configured hotkey. There is no default: nil until the user
    /// records a shortcut in Settings, and nil again after clearing it.
    static var stored: GlobalHotkey? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: keyCodeKey) != nil,
                  defaults.object(forKey: modifiersKey) != nil else {
                return nil
            }
            return GlobalHotkey(
                keyCode: UInt32(defaults.integer(forKey: keyCodeKey)),
                carbonModifiers: UInt32(defaults.integer(forKey: modifiersKey))
            )
        }
        set {
            let defaults = UserDefaults.standard
            if let newValue {
                defaults.set(Int(newValue.keyCode), forKey: keyCodeKey)
                defaults.set(Int(newValue.carbonModifiers), forKey: modifiersKey)
            } else {
                defaults.removeObject(forKey: keyCodeKey)
                defaults.removeObject(forKey: modifiersKey)
            }
        }
    }

    // MARK: - Display

    /// Human-readable form, e.g. "⌃⌥⌘S".
    var displayString: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "\u{2303}" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "\u{2325}" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "\u{21E7}" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "\u{2318}" }
        return symbols + keyLabel
    }

    private static let specialKeyLabels: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "\u{21A9}",
        UInt32(kVK_ANSI_KeypadEnter): "\u{2324}",
        UInt32(kVK_Tab): "\u{21E5}",
        UInt32(kVK_Delete): "\u{232B}",
        UInt32(kVK_ForwardDelete): "\u{2326}",
        UInt32(kVK_Escape): "\u{238B}",
        UInt32(kVK_LeftArrow): "\u{2190}",
        UInt32(kVK_RightArrow): "\u{2192}",
        UInt32(kVK_UpArrow): "\u{2191}",
        UInt32(kVK_DownArrow): "\u{2193}",
        UInt32(kVK_Home): "\u{2196}",
        UInt32(kVK_End): "\u{2198}",
        UInt32(kVK_PageUp): "\u{21DE}",
        UInt32(kVK_PageDown): "\u{21DF}",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    /// Label for the key itself, resolved against the current keyboard layout.
    var keyLabel: String {
        if let special = Self.specialKeyLabels[keyCode] { return special }

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return "?"
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}
