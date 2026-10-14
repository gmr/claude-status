import Foundation
import Testing
@testable import Claude_Status

struct TranscriptReaderTests {

    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func parsesConversationItems() {
        let user = line(["type": "user", "message": ["role": "user", "content": "Fix the build"]])
        #expect(TranscriptReader.parse(line: user) == [.user("Fix the build")])

        let assistant = line(["type": "assistant", "message": ["role": "assistant", "content": [
            ["type": "thinking", "thinking": "", "signature": "abc"],
            ["type": "text", "text": "Looking at it."],
            ["type": "tool_use", "name": "Bash", "input": ["command": "just test", "description": "Run tests"]],
        ]]])
        #expect(TranscriptReader.parse(line: assistant) == [
            .thinking, .assistant("Looking at it."), .toolUse(name: "Bash", summary: "Run tests"),
        ])

        let result = line(["type": "user", "message": ["role": "user", "content": [
            ["type": "tool_result", "content": [["type": "text", "text": "ok"]], "is_error": true],
        ]]])
        #expect(TranscriptReader.parse(line: result) == [.toolResult("ok", isError: true)])
    }

    @Test func skipsMetadataAndInjectedText() {
        #expect(TranscriptReader.parse(line: line(["type": "ai-title", "aiTitle": "x"])).isEmpty)
        #expect(TranscriptReader.parse(line: line(["type": "user", "isMeta": true, "message": ["content": "meta"]])).isEmpty)
        #expect(TranscriptReader.parse(line: line(["type": "user", "message": ["content": "<command-name>/clear</command-name>"]])).isEmpty)
        #expect(TranscriptReader.parse(line: Data("not json".utf8)).isEmpty)
    }

    @Test func summarizesQuestions() {
        let summary = TranscriptReader.toolSummary(name: "AskUserQuestion", input: [
            "questions": [["question": "Which window?"], ["question": "Merge now?"]],
        ])
        #expect(summary == "Which window?\nMerge now?")
    }

    @Test func readsTitles() {
        #expect(TranscriptReader.title(inLine: line(["type": "ai-title", "aiTitle": "Fix build"]))?.ai == "Fix build")
        #expect(TranscriptReader.title(inLine: line(["type": "custom-title", "customTitle": "GH-89"]))?.custom == "GH-89")
        #expect(TranscriptReader.title(inLine: line(["type": "user", "message": ["content": "hi"]])) == nil)
    }

    @Test func followsTitlesIncrementally() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        func append(_ object: [String: Any]) throws {
            var data = line(object)
            data.append(UInt8(ascii: "\n"))
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url)
            }
        }

        let cache = TranscriptTitleCache()
        try append(["type": "user", "message": ["content": "hi"]])
        #expect(cache.title(for: url) == nil)
        try append(["type": "ai-title", "aiTitle": "First"])
        #expect(cache.title(for: url) == "First")
        try append(["type": "ai-title", "aiTitle": "Second"])
        #expect(cache.title(for: url) == "Second")
        try append(["type": "custom-title", "customTitle": "Mine"])
        try append(["type": "ai-title", "aiTitle": "Third"])
        #expect(cache.title(for: url) == "Mine")
    }

    @Test func tailDropsCutFirstLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data()
        for index in 0..<50 {
            data.append(line(["type": "user", "message": ["content": "message \(index)"]]))
            data.append(UInt8(ascii: "\n"))
        }
        try data.write(to: url)

        let entries = TranscriptReader.tail(of: url, maxBytes: 300, limit: 60)
        #expect(!entries.isEmpty)
        #expect(entries.last?.kind == .user("message 49"))
        // Every entry parsed from a complete line.
        #expect(entries.allSatisfy { if case .user(let text) = $0.kind { text.hasPrefix("message ") } else { false } })
    }
}
