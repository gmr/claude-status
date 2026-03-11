import AppKit

// Menu bar-only app — pure AppKit entry point.
// NSStatusItem and NSPopover are managed by AppDelegate.

@MainActor
@main
struct Main {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
