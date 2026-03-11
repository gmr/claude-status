import Foundation

/// Resolves session state from JSONL files as a fallback for sessions without .cstatus files.
/// Also watches the projects directory for filesystem changes.
@MainActor
final class StateResolver {

    private static let claudeProjectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// Callback invoked when the projects directory changes.
    var onProjectsChanged: (() -> Void)?

    init() {
        setupFileWatcher()
    }

    deinit {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    /// Resolves state from JSONL modification times for a given project directory.
    /// Only used as a fallback when no .cstatus file is available.
    func resolveFromJSONL(in projectDir: URL) -> (state: SessionState, lastActivity: Date) {
        guard let (newestFile, lastModified) = mostRecentJSONLFile(in: projectDir) else {
            return (.idle, .distantPast)
        }

        let interval = Date().timeIntervalSince(lastModified)

        if interval < 5 {
            return (.active, lastModified)
        }

        let lastLineState = stateFromLastMeaningfulLine(of: newestFile)

        switch lastLineState {
        case .assistantWorking:
            if interval < 30 {
                return (.active, lastModified)
            }
            return (.waiting, lastModified)

        case .assistantDone:
            if interval < 10 {
                return (.active, lastModified)
            }
            return (.waiting, lastModified)

        case .userMessage:
            if interval < 30 {
                return (.active, lastModified)
            }
            return (.waiting, lastModified)

        case .noMeaningfulMessage:
            return (.idle, lastModified)
        }
    }

    // MARK: - File Watching

    private func setupFileWatcher() {
        let projectsPath = Self.claudeProjectsDir.path

        try? FileManager.default.createDirectory(
            at: Self.claudeProjectsDir,
            withIntermediateDirectories: true
        )

        fileDescriptor = open(projectsPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.onProjectsChanged?()
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        fileWatcher = source
    }

    // MARK: - JSONL Helpers

    private func mostRecentJSONLFile(in directory: URL) -> (URL, Date)? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        var newestURL: URL?
        var newestDate = Date.distantPast
        for url in contents where url.pathExtension == "jsonl" {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate,
               modified > newestDate {
                newestDate = modified
                newestURL = url
            }
        }

        guard let url = newestURL, newestDate != .distantPast else {
            return nil
        }
        return (url, newestDate)
    }

    // MARK: - Last Line Parsing

    private enum LastLineState {
        case assistantWorking
        case assistantDone
        case userMessage
        case noMeaningfulMessage
    }

    private static let meaningfulTypes: Set<String> = ["user", "assistant"]

    private func stateFromLastMeaningfulLine(of fileURL: URL) -> LastLineState {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return .noMeaningfulMessage
        }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            return .noMeaningfulMessage
        }

        let tailSize: UInt64 = min(fileSize, 64 * 1024)
        let seekPos = fileSize - tailSize

        do {
            try handle.seek(toOffset: seekPos)
        } catch {
            return .noMeaningfulMessage
        }

        guard let data = try? handle.read(upToCount: Int(tailSize)),
              let tail = String(data: data, encoding: .utf8) else {
            return .noMeaningfulMessage
        }

        let lines = tail.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let entryType = json["type"] as? String else {
                continue
            }

            guard Self.meaningfulTypes.contains(entryType) else {
                continue
            }

            return parseMessageState(from: json, entryType: entryType)
        }

        return .noMeaningfulMessage
    }

    private func parseMessageState(from json: [String: Any], entryType: String) -> LastLineState {
        if entryType == "user" {
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]],
               content.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                return .assistantWorking
            }
            return .userMessage
        }

        if entryType == "assistant" {
            if let message = json["message"] as? [String: Any] {
                let stopReason = message["stop_reason"] as? String
                if stopReason == "end_turn" { return .assistantDone }
                return .assistantWorking
            }
            return .assistantWorking
        }

        return .noMeaningfulMessage
    }
}
