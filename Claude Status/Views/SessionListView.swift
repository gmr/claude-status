import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The popover content showing all active Claude Code sessions.
struct SessionListView: View {
    let sessions: [ClaudeSession]
    let productivityData: ProductivityData
    /// Show per-session profile badges (when more than one profile is enabled).
    var showProfileBadges: Bool = false
    var onSessionTap: ((ClaudeSession) -> Void)?
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    @AppStorage("iconStyle", store: AppGroup.defaults)
    private var iconStyle: SessionIconStyle = .emoji

    @State private var isRefreshing = false
    @State private var selectedSessionID: String?
    @State private var keyMonitor: Any?
    @State private var keyMonitorState = KeyMonitorState()

    private let menuFont = Font.system(size: 13)

    private var sortedSessions: [ClaudeSession] {
        sessions.sortedByStateAndActivity
    }

    /// Max height for session list: 80% of screen height minus chrome.
    private var maxSessionListHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let chromeHeight: CGFloat = 160 // header + settings + menu + dividers
        return screenHeight * 0.8 - chromeHeight
    }

    var body: some View {
        // The retained key-monitor closure captured an older copy of this
        // struct; publish the current sessions and callbacks through the
        // shared box so keyboard actions never act on stale inputs (@State
        // reads stay live across copies).
        keyMonitorState.sortedSessions = sortedSessions
        keyMonitorState.onSessionTap = onSessionTap
        keyMonitorState.onRefresh = onRefresh
        keyMonitorState.onSettings = onSettings
        keyMonitorState.onQuit = onQuit

        return VStack(spacing: 0) {
            header
            Divider()

            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }

            if productivityData.today.totalSessionTime > 0 {
                Divider()
                    .padding(.vertical, 4)
                productivitySection
            }

            Divider()
                .padding(.vertical, 4)
            menuSection
        }
        .frame(width: 300)
        .background(.background)
        .onAppear {
            selectedSessionID = nil
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
    }

    // MARK: - Keyboard Navigation

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])

        // Command shortcuts mirror the header/menu buttons
        if modifiers == .command, let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "r":
                triggerRefresh()
                return nil
            case ",":
                keyMonitorState.onSettings?()
                return nil
            case "q":
                keyMonitorState.onQuit?()
                return nil
            default:
                break
            }
        }

        let currentSessions = keyMonitorState.sortedSessions
        guard !currentSessions.isEmpty, modifiers.isEmpty else { return event }

        // Digit keys 1-9 (0 = tenth row) jump straight to that session;
        // matched by key code so the mapping is keyboard-layout independent
        if let digit = Self.digitKeyCodes[Int(event.keyCode)],
           let index = Self.sessionIndex(forDigit: digit),
           index < currentSessions.count {
            keyMonitorState.onSessionTap?(currentSessions[index])
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_DownArrow:
            moveSelection(by: 1)
            return nil
        case kVK_UpArrow:
            moveSelection(by: -1)
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let selected = currentSessions.first(where: { $0.id == selectedSessionID }) else {
                return event
            }
            keyMonitorState.onSessionTap?(selected)
            return nil
        default:
            return event
        }
    }

    private static let digitKeyCodes: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9, kVK_ANSI_0: 0,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3,
        kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6,
        kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
        kVK_ANSI_Keypad0: 0,
    ]

    private func triggerRefresh() {
        withAnimation(.linear(duration: 0.5)) {
            isRefreshing = true
        }
        keyMonitorState.onRefresh?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isRefreshing = false
        }
    }

    private func moveSelection(by delta: Int) {
        let list = keyMonitorState.sortedSessions
        let current = list.firstIndex { $0.id == selectedSessionID }
        guard let next = Self.nextSelectionIndex(current: current, delta: delta, count: list.count) else {
            return
        }
        selectedSessionID = list[next].id
    }

    /// Pure index math for arrow-key navigation: wraps at both ends; with no
    /// current selection, down selects the first row and up selects the last.
    static func nextSelectionIndex(current: Int?, delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current, (0..<count).contains(current) else {
            return delta >= 0 ? 0 : count - 1
        }
        return (current + delta % count + count) % count
    }

    /// Maps a pressed digit key to a session row: 1-9 select rows 0-8, 0
    /// selects the tenth row.
    static func sessionIndex(forDigit digit: Int) -> Int? {
        guard (0...9).contains(digit) else { return nil }
        return digit == 0 ? 9 : digit - 1
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("Claude Status")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("v\(Bundle.main.appVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: triggerRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(.linear(duration: 0.5), value: isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh (\u{2318}R)")

            Button(action: { onSettings?() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings (\u{2318},)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No active sessions")
                .font(menuFont)
                .foregroundStyle(.secondary)
            Text("Sessions appear when claude is running")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var sessionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            onSessionTap?(session)
                        } label: {
                            SessionRowView(
                                session: session,
                                iconStyle: iconStyle,
                                showProfileBadge: showProfileBadges,
                                isSelected: session.id == selectedSessionID,
                                shortcutHint: index < 10 ? (index + 1) % 10 : nil
                            )
                        }
                        .buttonStyle(.plain)
                        .id(session.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedSessionID) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue)
                }
            }
        }
        .frame(maxHeight: maxSessionListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var productivitySection: some View {
        let stats = productivityData.today
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Claude Usage (Today)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.totalTimeFormatted) · Score \(stats.score)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Stacked horizontal bar — hover shows floating legend tooltip
            ProductivityBarView(stats: stats)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var menuSection: some View {
        VStack(spacing: 0) {
            menuButton(action: { onQuit?() }) {
                HStack {
                    Text("Quit")
                    Spacer()
                    Text("\u{2318}Q")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func menuButton<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        MenuButtonView(action: action, label: label)
            .font(menuFont)
    }
}

/// Reference box shared between the view and its retained key-monitor
/// closure. The closure captures a value copy of `SessionListView` from when
/// the monitor was installed; `@State` reads stay live across copies, but the
/// sessions and callback properties would be frozen at install time without
/// this.
private final class KeyMonitorState {
    var sortedSessions: [ClaudeSession] = []
    var onSessionTap: ((ClaudeSession) -> Void)?
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
}

/// A menu-style button with hover highlight, similar to Claude Code's menu items.
private struct MenuButtonView<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                        .padding(.horizontal, 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

}
