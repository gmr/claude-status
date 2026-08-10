import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via the Carbon hotkey API (no accessibility
/// permission required) and invokes a callback when it is pressed.
@MainActor
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Registers `hotkey` as the active global shortcut, replacing any
    /// previous registration. Returns false when the system rejects the
    /// registration (e.g. the combination is reserved), leaving no shortcut
    /// active.
    @discardableResult
    func register(_ hotkey: GlobalHotkey) -> Bool {
        unregister()
        guard installHandlerIfNeeded() else { return false }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4353_5453) /* "CSTS" */, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, ref != nil else {
            NSLog("Claude Status: failed to register global hotkey %@ (OSStatus %d)",
                  hotkey.displayString, status)
            return false
        }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() -> Bool {
        if eventHandlerRef != nil { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr {
            NSLog("Claude Status: failed to install hotkey event handler (OSStatus %d)", status)
        }
        return eventHandlerRef != nil
    }
}

/// Carbon event callback; must be a plain C-convention function. Carbon
/// dispatches these on the main thread.
private nonisolated func hotkeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.onHotkey?()
    }
    return noErr
}
