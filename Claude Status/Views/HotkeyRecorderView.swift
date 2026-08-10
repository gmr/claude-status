import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A click-to-record control for capturing a global keyboard shortcut.
/// Click to start recording, press a key combination to set it, Esc to cancel.
struct HotkeyRecorderView: View {
    @Binding var hotkey: GlobalHotkey?
    /// Called when recording starts/stops so the active global hotkey can be
    /// suspended while the user types the new one.
    var onRecordingChanged: ((Bool) -> Void)?

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    private var buttonLabel: String {
        if isRecording {
            "Type shortcut\u{2026}"
        } else {
            hotkey?.displayString ?? "Record Shortcut"
        }
    }

    var body: some View {
        Button(action: toggleRecording) {
            Text(buttonLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .help("Click, then press the new shortcut. Esc cancels.")
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard keyMonitor == nil else { return }
        isRecording = true
        onRecordingChanged?(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            guard let captured = GlobalHotkey(event: event) else {
                // Needs at least one non-shift modifier
                NSSound.beep()
                return nil
            }
            hotkey = captured
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChanged?(false)
    }
}
