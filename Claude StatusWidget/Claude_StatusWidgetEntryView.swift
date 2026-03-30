import SwiftUI
import WidgetKit

// MARK: - Vibrant-safe foreground styles
//
// Desktop widgets render in `.vibrant` mode. When the user enables
// "Dim widgets on desktop", the system multiplies an extra alpha on top
// of the vibrancy effect.  Hierarchical styles like `.secondary` and
// `.tertiary` already have reduced opacity, so after the dimming
// multiplier they fall to near-zero contrast and become invisible.
//
// Using `.primary` with explicit opacity values keeps text readable
// in both dimmed and un-dimmed vibrant states.

extension View {
    /// Foreground style that stays visible when desktop widgets are dimmed.
    /// In full-color mode (sidebar / Notification Center) it uses the real
    /// hierarchical style; in vibrant mode it substitutes `.primary` with an
    /// opacity high enough to survive the dimming multiplier.
    @ViewBuilder
    func widgetForeground(
        _ style: HierarchicalShapeStyle,
        opacity vibrantOpacity: Double,
        isFullColor: Bool
    ) -> some View {
        if isFullColor {
            self.foregroundStyle(style)
        } else {
            self.foregroundStyle(.primary.opacity(vibrantOpacity))
        }
    }
}

/// The SwiftUI view for the Claude Status widget entry.
struct Claude_StatusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SessionEntry

    var body: some View {
        switch family {
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: SessionEntry

    private var isFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.sessions.isEmpty {
                emptyState
            } else {
                sessionList(maxRows: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("\u{1F4A4}")
                    .font(.system(size: 24))
                Text("No active sessions")
                    .font(.system(size: 12))
                    .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
            }
            Spacer()
        }
        Spacer()
    }

    @ViewBuilder
    private func sessionList(maxRows: Int) -> some View {
        let sessions = Array(sortedSessions.prefix(maxRows))
        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
            if index > 0 {
                Divider()
                    .padding(.leading, 32)
            }
            Link(destination: session.deepLinkURL) {
                SessionRowWidget(session: session)
            }
            .buttonStyle(.plain)
        }
        if entry.sessions.count > maxRows {
            Divider()
                .padding(.leading, 32)
            HStack {
                Spacer()
                Text("+\(entry.sessions.count - maxRows) more")
                    .font(.system(size: 11))
                    .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var sortedSessions: [ClaudeSession] {
        entry.sessions.sortedByStateAndActivity
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: SessionEntry

    private var isFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.sessions.isEmpty {
                emptyState
            } else {
                sessionList(maxRows: 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("\u{1F4A4}")
                    .font(.system(size: 28))
                Text("No active sessions")
                    .font(.system(size: 12))
                    .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
            }
            Spacer()
        }
        Spacer()
    }

    @ViewBuilder
    private func sessionList(maxRows: Int) -> some View {
        let sessions = Array(sortedSessions.prefix(maxRows))
        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
            if index > 0 {
                Divider()
                    .padding(.leading, 32)
            }
            Link(destination: session.deepLinkURL) {
                SessionRowWidget(session: session)
            }
            .buttonStyle(.plain)
        }
        if entry.sessions.count > maxRows {
            Divider()
                .padding(.leading, 32)
            HStack {
                Spacer()
                Text("+\(entry.sessions.count - maxRows) more")
                    .font(.system(size: 11))
                    .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var sortedSessions: [ClaudeSession] {
        entry.sessions.sortedByStateAndActivity
    }
}

// MARK: - Session Row

/// A single session row matching the system widget style — icon, text, value aligned.
/// Desktop (vibrant): always emoji — shapes are more distinguishable when desaturated.
/// Sidebar (full color): respects the user's icon style preference (emoji or dots).
struct SessionRowWidget: View {
    @Environment(\.widgetRenderingMode) var renderingMode
    let session: ClaudeSession

    private var isFullColor: Bool { renderingMode == .fullColor }

    /// Read the user's icon style preference from the shared App Group defaults.
    private var iconStyle: String {
        UserDefaults(suiteName: "group.com.poisonpenllc.Claude-Status")?
            .string(forKey: "iconStyle") ?? "emoji"
    }

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.sessionName ?? session.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 3) {
                    if session.sessionName != nil {
                        Text(session.projectName)
                            .font(.system(size: 10))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                        Text("\u{2022}")
                            .font(.system(size: 7))
                            .widgetForeground(.quaternary, opacity: 0.5, isFullColor: isFullColor)
                    }
                    Text(session.source.label)
                        .font(.system(size: 10))
                        .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                    if !session.activity.isEmpty {
                        Text("\u{2022}")
                            .font(.system(size: 7))
                            .widgetForeground(.quaternary, opacity: 0.5, isFullColor: isFullColor)
                        Text(session.activity)
                            .font(.system(size: 10))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(session.state.label)
                    .font(.system(size: 11))
                Text(session.timeSinceActivity)
                    .font(.system(size: 10))
                    .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        // Only show dots when in full-color mode (sidebar) with dots preference.
        // Default to emoji everywhere else — emoji shapes are more distinguishable
        // on the desktop where colors are desaturated.
        if renderingMode == .fullColor, iconStyle == "dots" {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
        } else {
            Text(session.state.emoji)
                .font(.system(size: 14))
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
