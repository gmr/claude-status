import SwiftUI
import WidgetKit


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
    let entry: SessionEntry

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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
    let entry: SessionEntry

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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
struct SessionRowWidget: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 10) {
            Text(session.state.emoji)
                .font(.system(size: 14))
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Text(session.source.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if !session.activity.isEmpty {
                        Text("\u{2022}")
                            .font(.system(size: 7))
                            .foregroundStyle(.quaternary)
                        Text(session.activity)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 10)
    }
}
