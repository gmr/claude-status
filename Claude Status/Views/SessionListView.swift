import SwiftUI

/// The popover content showing all active Claude Code sessions.
struct SessionListView: View {
    let sessions: [ClaudeSession]
    var onSessionTap: ((ClaudeSession) -> Void)?
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    @AppStorage("iconStyle", store: UserDefaults(suiteName: "group.com.poisonpenllc.Claude-Status"))
    private var iconStyle: SessionIconStyle = .emoji

    private let menuFont = Font.system(size: 13)

    /// Sessions sorted by state: Waiting, Active, Idle.
    private var sortedSessions: [ClaudeSession] {
        sessions.sorted { $0.state.sortOrder < $1.state.sortOrder }
    }

    /// Max height for session list: 80% of screen height minus chrome.
    private var maxSessionListHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let chromeHeight: CGFloat = 160 // header + settings + menu + dividers
        return screenHeight * 0.8 - chromeHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }

            Divider()
                .padding(.vertical, 4)
            menuSection
        }
        .frame(width: 300)
        .background(.background)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Claude Status")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { onRefresh?() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
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
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sortedSessions) { session in
                    Button {
                        onSessionTap?(session)
                    } label: {
                        SessionRowView(session: session, iconStyle: iconStyle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: maxSessionListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var menuSection: some View {
        VStack(spacing: 0) {
            menuButton(action: { onSettings?() }) {
                Text("Settings\u{2026}")
            }
            menuButton(action: { onQuit?() }) {
                Text("Quit")
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

extension SessionIconStyle: RawRepresentable {}
