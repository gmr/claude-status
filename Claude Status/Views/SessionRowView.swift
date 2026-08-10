import SwiftUI

/// Icon display style for session rows.
enum SessionIconStyle: String, CaseIterable {
    case emoji
    case dots

    var label: String {
        switch self {
        case .emoji: "Emoji"
        case .dots: "Dots"
        }
    }
}

/// A single row in the session list showing status, project name, and time.
struct SessionRowView: View {
    let session: ClaudeSession
    var iconStyle: SessionIconStyle = .emoji
    /// Show which profile the session belongs to (multi-profile setups).
    var showProfileBadge: Bool = false
    /// Highlighted via keyboard navigation.
    var isSelected: Bool = false
    /// Digit key that jumps to this row (1-9, 0 for the tenth row).
    var shortcutHint: Int? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(shortcutHint.map(String.init) ?? "")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 8, alignment: .trailing)

            statusIndicator
                .frame(width: 16, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.sessionName ?? session.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if showProfileBadge, let profileName = session.profileName {
                        Text(profileName)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    if session.sessionName != nil {
                        Text(session.projectName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\u{2022}")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    Text(session.source.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if !session.activity.isEmpty {
                        Text("\u{2022}")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(session.activity)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(session.state.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                Text(session.timeSinceActivity)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlightColor)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(session.workingDirectory)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch iconStyle {
        case .emoji:
            Text(session.state.emoji)
                .font(.system(size: 14))
        case .dots:
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
        }
    }

    private var highlightColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.25)
        } else if isHovered {
            Color.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }

    private var dotColor: Color {
        switch session.state {
        case .active: .green
        case .waiting: .orange
        case .compacting: .blue
        case .idle: .gray
        }
    }
}
