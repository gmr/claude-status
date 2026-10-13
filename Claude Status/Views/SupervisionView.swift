import SwiftUI

/// Supervision window: every session on the left, a live preview of the
/// selected conversation on the right.
struct SupervisionView: View {
    @Bindable var monitor: SessionMonitor
    var onOpen: (ClaudeSession) -> Void

    @AppStorage("iconStyle", store: AppGroup.defaults)
    private var iconStyle: SessionIconStyle = .emoji
    @State private var selectedId: String?

    private var sessions: [ClaudeSession] {
        monitor.sessions.sortedByStateAndActivity
    }

    private var selected: ClaudeSession? {
        sessions.first { $0.id == selectedId }
    }

    var body: some View {
        NavigationSplitView {
            List(sessions, selection: $selectedId) { session in
                SessionRowView(
                    session: session,
                    iconStyle: iconStyle,
                    showProfileBadge: monitor.profileStore.enabledProfiles.count > 1
                )
                .padding(.horizontal, -14)
                .tag(session.id)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No Active Sessions", systemImage: "moon.zzz")
                }
            }
        } detail: {
            if let session = selected {
                ConversationPreviewView(session: session) { onOpen(session) }
                    .id(session.id)
            } else {
                ContentUnavailableView("Select a Session", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: sessions.map(\.id)) { selectFirstIfNeeded() }
    }

    /// Keeps a selection while sessions come and go.
    private func selectFirstIfNeeded() {
        if selected == nil {
            selectedId = sessions.first?.id
        }
    }
}

/// Live, read-only view of the end of a conversation.
struct ConversationPreviewView: View {
    let session: ClaudeSession
    var onOpen: () -> Void

    @State private var entries: [TranscriptEntry] = []
    @State private var lastFileSize: UInt64?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if session.state == .waiting {
                Divider()
                waitingBanner
            }
        }
        .task(id: session.id) {
            while !Task.isCancelled {
                reload()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.headline)
                Text(session.displayTitle ?? "New conversation")
                    .font(.subheadline)
                    .foregroundStyle(session.displayTitle == nil ? .tertiary : .primary)
                Text("\(session.source.label) \u{2022} \(session.state.label) \u{2022} \(session.timeSinceActivity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open in \(session.source.label)", action: onOpen)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if entries.isEmpty {
                        Text("Nothing to show yet.")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(entries) { entry in
                        TranscriptEntryView(entry: entry)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
                .textSelection(.enabled)
            }
            .onChange(of: entries) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var waitingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hourglass")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for your answer")
                    .font(.subheadline.weight(.semibold))
                if let question = pendingQuestion {
                    Text(question)
                        .font(.callout)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    /// The last thing Claude said or asked, shown while the session waits.
    private var pendingQuestion: String? {
        for entry in entries.reversed() {
            switch entry.kind {
            case .toolUse(let name, let summary) where name == "AskUserQuestion":
                return summary
            case .assistant(let text):
                return text
            case .user:
                return nil
            default:
                continue
            }
        }
        return nil
    }

    /// Re-parses the transcript tail when the file grew.
    private func reload() {
        guard let path = session.transcriptPath else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? nil
        guard size != lastFileSize else { return }
        lastFileSize = size
        entries = TranscriptReader.tail(of: URL(fileURLWithPath: path))
    }
}

/// One item of the conversation preview.
private struct TranscriptEntryView: View {
    let entry: TranscriptEntry

    var body: some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        case .assistant(let text):
            Text(markdown(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking:
            Label("Thinking\u{2026}", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .toolUse(let name, let summary):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: name == "AskUserQuestion" ? "questionmark.bubble" : "wrench.and.screwdriver")
                    .foregroundStyle(name == "AskUserQuestion" ? .orange : .secondary)
                Text(name)
                    .fontWeight(.medium)
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(name == "AskUserQuestion" ? nil : 2)
            }
            .font(.system(size: 11, design: .monospaced))
        case .toolResult(let text, let isError):
            Text(text.isEmpty ? "(no output)" : String(text.prefix(400)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isError ? .red : .secondary)
                .lineLimit(4)
                .padding(.leading, 20)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
