import AppKit
import RollbarNotifier
import Sparkle
import SwiftUI

/// App delegate managing the menu bar status item and popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = SessionMonitor()
    private let focuser = SessionFocuser()
    private let pluginInstaller = PluginInstaller()
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?

    /// Sparkle updater controller for automatic updates.
    /// Only initialized when a valid EdDSA public key is present in Info.plist.
    private(set) var updaterController: SPUStandardUpdaterController?

    /// Whether Sparkle is available (valid EdDSA key configured).
    var isSparkleAvailable: Bool { updaterController != nil }

    /// Shared defaults for the app group (cached to avoid per-tick allocation).
    private let sharedDefaults = UserDefaults(suiteName: "group.com.poisonpenllc.Claude-Status")

    /// Cached state for change detection in status icon updates.
    private var lastRenderedState: SessionState?
    private var lastRenderedHookMissing: Bool = false
    private var lastRenderedIconStyle: SessionIconStyle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip UI setup when running under XCTest to avoid blocking the test runner
        guard !isRunningTests else { return }

        setupRollbar()
        setupMainMenu()
        setupStatusItem()
        setupPopover()
        setupURLHandler()
        monitor.start()

        // Initialize Sparkle only if a valid EdDSA public key is configured
        if let edKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           !edKey.isEmpty {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }

        // Check plugin installation on startup (after a short delay to let the monitor start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPluginInstallation()
        }
    }

    private func setupRollbar() {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "RollbarAccessToken") as? String,
              !token.isEmpty else {
            return
        }
        let config = RollbarConfig.mutableConfig(withAccessToken: token)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        config.setServerHost(nil, root: nil, branch: nil, codeVersion: version)
        Rollbar.initWithConfiguration(config)
    }

    private var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Claude Status", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateStatusIcon()

        // Observe session changes to update status indicator
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Defer to avoid layout recursion if the status bar is mid-layout
            DispatchQueue.main.async {
                self?.updateStatusIcon()
            }
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshSessions), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Status", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click still opens popover
        statusItem.menu = nil
    }

    @objc private func refreshSessions() {
        monitor.refresh()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let hookMissing = monitor.hookDetected == false
        let aggregateState = monitor.aggregateState
        let iconStyle = sharedDefaults.flatMap { defaults in
            defaults.string(forKey: "iconStyle").flatMap { SessionIconStyle(rawValue: $0) }
        } ?? .emoji

        // Skip redraw if nothing has changed
        if aggregateState == lastRenderedState
            && hookMissing == lastRenderedHookMissing
            && iconStyle == lastRenderedIconStyle {
            return
        }
        lastRenderedState = aggregateState
        lastRenderedHookMissing = hookMissing
        lastRenderedIconStyle = iconStyle

        // Get the base icon
        let baseIcon: NSImage
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.size = NSSize(width: 18, height: 18)
            baseIcon = icon
        } else {
            baseIcon = NSImage(
                systemSymbolName: "terminal",
                accessibilityDescription: "Claude Status"
            ) ?? NSImage()
        }

        guard let state = aggregateState else {
            // No sessions — just show the template icon
            baseIcon.isTemplate = true
            button.image = baseIcon
            button.title = ""
            return
        }
        let useEmoji = iconStyle != .dots

        if useEmoji {
            // Emoji mode: compose icon with emoji overlay in bottom-right
            let iconSize = baseIcon.size
            let emojiFont = NSFont.systemFont(ofSize: 12)
            let emojiStr = state.emoji as NSString
            let emojiAttrs: [NSAttributedString.Key: Any] = [.font: emojiFont]
            let emojiSize = emojiStr.size(withAttributes: emojiAttrs)
            let gap: CGFloat = 2

            let canvasSize = NSSize(
                width: iconSize.width + emojiSize.width / 2 + gap,
                height: iconSize.height
            )
            let composed = NSImage(size: canvasSize, flipped: false) { _ in
                // Draw the base icon tinted for light/dark
                baseIcon.isTemplate = false
                let tintColor: NSColor = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .white
                    : .black
                let tinted = baseIcon.tinted(with: tintColor)
                tinted.draw(in: NSRect(origin: .zero, size: iconSize))

                // Position emoji in bottom-right overlapping the icon
                let emojiRect = NSRect(
                    x: iconSize.width - emojiSize.width / 2,
                    y: -1,
                    width: emojiSize.width,
                    height: emojiSize.height
                )

                // Draw the emoji directly (no clear ring)
                emojiStr.draw(in: emojiRect, withAttributes: emojiAttrs)

                return true
            }

            composed.isTemplate = false
            button.image = composed
            button.title = ""
        } else {
            // Dot mode: compose icon with colored dot badge (and exclamation if hook missing)
            let iconSize = baseIcon.size
            let dotDiameter: CGFloat = 10
            let gap: CGFloat = 2
            let exclamationWidth: CGFloat = hookMissing ? 8 : 0
            let canvasSize = NSSize(
                width: iconSize.width + dotDiameter / 2 + gap + exclamationWidth,
                height: iconSize.height
            )
            let composed = NSImage(size: canvasSize, flipped: false) { _ in
                baseIcon.isTemplate = false
                let tintColor: NSColor = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .white
                    : .black
                let tinted = baseIcon.tinted(with: tintColor)
                tinted.draw(in: NSRect(origin: .zero, size: iconSize))

                let dotRect = NSRect(
                    x: iconSize.width - dotDiameter / 2,
                    y: 0,
                    width: dotDiameter,
                    height: dotDiameter
                )

                let clearRect = dotRect.insetBy(dx: -gap, dy: -gap)
                guard let context = NSGraphicsContext.current?.cgContext else { return true }
                context.setBlendMode(.clear)
                context.fillEllipse(in: clearRect)
                context.setBlendMode(.normal)

                let dotColor: NSColor = switch state {
                case .waiting: .systemOrange
                case .active: .systemGreen
                case .compacting: .systemBlue
                case .idle: .systemGray
                }

                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()

                // Draw exclamation mark overlay when hook is missing
                if hookMissing {
                    let exclamation = "!" as NSString
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: NSColor.systemYellow,
                    ]
                    let excSize = exclamation.size(withAttributes: attrs)
                    let excRect = NSRect(
                        x: canvasSize.width - excSize.width,
                        y: (canvasSize.height - excSize.height) / 2,
                        width: excSize.width,
                        height: excSize.height
                    )
                    exclamation.draw(in: excRect, withAttributes: attrs)
                }

                return true
            }

            composed.isTemplate = false
            button.image = composed
            button.title = ""
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover.behavior = .transient
        popover.appearance = nil
        let hostingController = NSHostingController(
            rootView: PopoverContentView(
                monitor: monitor,
                onSessionTap: { [weak self] session in
                    self?.closePopover()
                    self?.focuser.focus(session: session)
                },
                onRefresh: { [weak self] in
                    self?.monitor.refresh()
                },
                onSettings: { [weak self] in
                    self?.closePopover()
                    self?.showSettings()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )
        hostingController.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        popover.contentViewController = hostingController
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            monitor.refresh()
            guard let button = statusItem.button else { return }
            // Defer to next run loop tick to avoid layout recursion
            DispatchQueue.main.async { [weak self] in
                self?.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - Plugin Installation

    /// Key to track whether we've already shown the install prompt this launch.
    private static let pluginPromptShownKey = "pluginInstallPromptShown"

    private func checkPluginInstallation() {
        let detector = PluginDetector()
        let state = detector.detect()

        if state == .installed {
            // Check if the installed version matches the bundled version
            checkPluginVersionAndUpdate(detector: detector)
            return
        }

        guard state == .notInstalled else { return }

        // Only show the dialog once per app version to avoid nagging
        let lastPromptVersion = UserDefaults.standard.string(forKey: Self.pluginPromptShownKey)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if lastPromptVersion == currentVersion { return }

        UserDefaults.standard.set(currentVersion, forKey: Self.pluginPromptShownKey)
        showPluginInstallDialog()
    }

    /// Silently reinstalls the plugin if the installed version doesn't match the bundled version.
    private func checkPluginVersionAndUpdate(detector: PluginDetector) {
        guard let bundledVersion = pluginInstaller.bundledPluginVersion,
              let installedVersion = detector.installedPluginVersion(),
              bundledVersion != installedVersion else {
            return
        }

        // Version mismatch — reinstall silently on a background queue
        // to avoid blocking the main thread with CLI operations
        let installer = pluginInstaller
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let uninstallError = installer.uninstall() {
                NSLog("Claude Status: plugin uninstall failed during auto-update: %@", uninstallError)
                return
            }
            if let error = installer.install() {
                NSLog("Claude Status: plugin auto-update from %@ to %@ failed: %@",
                      installedVersion, bundledVersion, error)
            } else {
                NSLog("Claude Status: plugin auto-updated from %@ to %@",
                      installedVersion, bundledVersion)
                DispatchQueue.main.async {
                    self?.monitor.invalidatePluginCache()
                    self?.monitor.refresh()
                }
            }
        }
    }

    private func showPluginInstallDialog() {
        let alert = NSAlert()
        alert.messageText = "Install Claude Code Plugin?"
        alert.informativeText = "Claude Status requires a Claude Code plugin to report session activity. The plugin registers lightweight hooks that write status files as Claude works.\n\nYou can also install it later from the status menu."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Plugin")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            performPluginInstall()
        }
    }

    func performPluginUninstall() {
        if let error = pluginInstaller.uninstall() {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Plugin Uninstall Failed"
            errorAlert.informativeText = error
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        } else {
            monitor.invalidatePluginCache()
            monitor.refresh()

            let successAlert = NSAlert()
            successAlert.messageText = "Plugin Uninstalled"
            successAlert.informativeText = "The Claude Status plugin has been removed. Session activity will no longer be reported."
            successAlert.alertStyle = .informational
            successAlert.runModal()
        }
    }

    func performPluginInstall() {
        if let error = pluginInstaller.install() {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Plugin Installation Failed"
            errorAlert.informativeText = error
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        } else {
            // Clear the hookDetected = false state so the warning disappears
            monitor.invalidatePluginCache()
            monitor.refresh()

            let successAlert = NSAlert()
            successAlert.messageText = "Plugin Installed"
            successAlert.informativeText = "The Claude Status plugin has been installed. It will activate the next time a Claude Code session starts."
            successAlert.alertStyle = .informational
            successAlert.runModal()
        }
    }

    // MARK: - Settings Window

    private func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let pluginState = PluginDetector().detect()
        let settingsView = SettingsView(
            pluginState: pluginState,
            updater: updaterController?.updater,
            onInstallPlugin: { [weak self] in
                self?.performPluginInstall()
                // Reopen settings to reflect new state
                self?.settingsWindow?.close()
                self?.showSettings()
            },
            onUninstallPlugin: { [weak self] in
                self?.performPluginUninstall()
                self?.settingsWindow?.close()
                self?.showSettings()
            }
        )

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Claude Status Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    // MARK: - Deep Link Handler

    private func setupURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        handleDeepLink(url)
    }

    private func handleDeepLink(_ url: URL) {
        // Handle claude-status://session/{sessionId} URLs from widget
        guard url.scheme == "claude-status",
              url.host == "session",
              let sessionId = url.pathComponents.dropFirst().first else {
            return
        }

        // Find the session by ID
        guard let session = monitor.sessions.first(where: { $0.id == sessionId }) else {
            return
        }

        // Focus the session's host app
        focuser.focus(session: session)
    }
}

// MARK: - NSImage Tinting

private extension NSImage {
    /// Returns a copy of the image tinted with the given color.
    func tinted(with color: NSColor) -> NSImage {
        let imageSize = self.size
        return NSImage(size: imageSize, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// SwiftUI wrapper that observes the monitor for the popover.
private struct PopoverContentView: View {
    @Bindable var monitor: SessionMonitor
    var onSessionTap: (ClaudeSession) -> Void
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        SessionListView(
            sessions: monitor.sessions,
            productivityData: monitor.productivityData,
            onSessionTap: onSessionTap,
            onRefresh: onRefresh,
            onSettings: onSettings,
            onQuit: onQuit
        )
    }
}
