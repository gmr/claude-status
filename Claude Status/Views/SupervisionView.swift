import SwiftUI
import WebKit

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
            ConversationWebView(
                entries: entries,
                waitingQuestion: session.state == .waiting ? pendingQuestion ?? "" : nil
            )
            Divider()
            footer
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
        }
        .padding(12)
    }

    /// Bottom left, where the IDE's prompt box sits: the hand is already there.
    private var footer: some View {
        HStack {
            Button("Open in \(session.source.label)", action: onOpen)
                .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

/// Renders the conversation with `conversation.html` (bundled marked + mermaid),
/// so markdown, tables and diagrams display as they do in the IDE.
struct ConversationWebView: NSViewRepresentable {
    let entries: [TranscriptEntry]
    /// Question to pin at the bottom while the session waits; nil otherwise.
    let waitingQuestion: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        if let page = Bundle.main.url(forResource: "conversation", withExtension: "html") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(payload(), in: webView)
    }

    private func payload() -> String {
        let items: [[String: Any]] = entries.map { entry in
            switch entry.kind {
            case .user(let text): ["kind": "user", "text": text]
            case .assistant(let text): ["kind": "assistant", "text": text]
            case .thinking: ["kind": "thinking"]
            case .toolUse(let name, let summary): ["kind": "tool", "name": name, "text": summary]
            case .toolResult(let text, let isError): ["kind": "result", "text": String(text.prefix(2000)), "isError": isError]
            }
        }
        let object: [String: Any] = ["entries": items, "waiting": waitingQuestion ?? NSNull()]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var isLoaded = false
        private var pending: String?
        private var shown: String?

        /// Sends the payload once the page is loaded, skipping unchanged content.
        func show(_ payload: String, in webView: WKWebView) {
            guard payload != shown else { return }
            guard isLoaded else {
                pending = payload
                return
            }
            let firstRender = shown == nil
            shown = payload
            let call = firstRender
                ? "render(Object.assign(\(payload), {scrollToBottom: true}))"
                : "render(\(payload))"
            webView.evaluateJavaScript(call)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending {
                self.pending = nil
                show(pending, in: webView)
            }
        }

        /// Links open in the default browser; the page itself never navigates.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
