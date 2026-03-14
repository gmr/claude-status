import AppKit

// Menu bar-only app — pure AppKit entry point.
// NSStatusItem and NSPopover are managed by AppDelegate.

@MainActor
@main
struct Main {
    static func main() {
        // Enforce single instance — if another copy is already running, activate it and exit.
        guard let bundleID = Bundle.main.bundleIdentifier else {
            assertionFailure("Missing bundle identifier")
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            // Activate the other instance (the one that isn't us)
            let me = ProcessInfo.processInfo.processIdentifier
            if let other = running.first(where: { $0.processIdentifier != me }) {
                other.activate()
            }
            exit(0)
        }

        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
