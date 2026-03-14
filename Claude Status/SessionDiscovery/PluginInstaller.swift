import Foundation

/// Installs the bundled Claude Status plugin using the Claude Code CLI.
///
/// The app bundles a complete plugin marketplace in its Resources directory.
/// Installation runs two CLI commands:
/// 1. `claude plugin marketplace add <path>` — registers the bundled marketplace
/// 2. `claude plugin install claude-status@claude-status-marketplace` — installs the plugin
struct PluginInstaller {

    static let marketplaceName = "claude-status-marketplace"
    static let pluginKey = "claude-status@claude-status-marketplace"

    /// Path to the bundled marketplace inside the app bundle.
    var bundledMarketplacePath: String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("claude-status-plugin")
            .path
    }

    /// Version of the bundled plugin (read from the plugin's own plugin.json).
    var bundledPluginVersion: String? {
        guard let marketplacePath = bundledMarketplacePath else { return nil }
        let pluginJSON = URL(fileURLWithPath: marketplacePath)
            .appendingPathComponent("plugins/claude-status/.claude-plugin/plugin.json")
        guard let data = try? Data(contentsOf: pluginJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }
        return version
    }

    /// Resolves the `claude` CLI binary path.
    private var claudePath: String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/claude").path,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Install

    /// Installs the plugin via the Claude CLI. Returns nil on success, or an error message.
    func install() -> String? {
        guard let claude = claudePath else {
            return "Claude Code CLI not found. Install it first: https://docs.anthropic.com/en/docs/claude-code/overview"
        }

        guard let marketplacePath = bundledMarketplacePath else {
            return "Bundled marketplace not found in app resources"
        }

        // 1. Add the marketplace
        let addResult = runCLI(claude, arguments: [
            "plugin", "marketplace", "add", marketplacePath,
        ])
        if let error = addResult {
            // Ignore "already exists" errors
            if !error.contains("already") {
                return "Failed to add marketplace: \(error)"
            }
        }

        // 2. Install the plugin
        let installResult = runCLI(claude, arguments: [
            "plugin", "install", Self.pluginKey,
        ])
        if let error = installResult {
            // Ignore "already installed" errors
            if !error.contains("already") {
                return "Failed to install plugin: \(error)"
            }
        }

        return nil
    }

    // MARK: - Uninstall

    /// Uninstalls the plugin via the Claude CLI. Returns nil on success, or an error message.
    func uninstall() -> String? {
        guard let claude = claudePath else {
            return "Claude Code CLI not found."
        }

        // 1. Uninstall the plugin
        let uninstallResult = runCLI(claude, arguments: [
            "plugin", "uninstall", Self.pluginKey,
        ])
        if let error = uninstallResult {
            if !error.contains("not installed") && !error.contains("not found") {
                return "Failed to uninstall plugin: \(error)"
            }
        }

        // 2. Remove the marketplace
        let removeResult = runCLI(claude, arguments: [
            "plugin", "marketplace", "remove", Self.marketplaceName,
        ])
        if let error = removeResult {
            if !error.contains("not found") && !error.contains("not registered") {
                return "Failed to remove marketplace: \(error)"
            }
        }

        return nil
    }

    // MARK: - CLI Runner

    /// Runs a CLI command and returns nil on success, or the stderr/error on failure.
    /// Reads pipe output before waiting to prevent deadlock when pipe buffers fill.
    private func runCLI(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        // Inherit the user's PATH for any dependencies
        var env = ProcessInfo.processInfo.environment
        let homedir = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(homedir)/.local/bin:/usr/local/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        // Read pipe output asynchronously to prevent deadlock when buffers fill.
        // Use a serial queue to synchronize access to the mutable Data buffers.
        let pipeQueue = DispatchQueue(label: "com.poisonpenllc.Claude-Status.pipeIO")
        var stderrData = Data()
        var stdoutData = Data()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            pipeQueue.sync { stderrData.append(chunk) }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            pipeQueue.sync { stdoutData.append(chunk) }
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            return error.localizedDescription
        }

        // Timeout after 30 seconds to avoid blocking the app indefinitely
        let deadline = DispatchTime.now() + .seconds(30)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            return "CLI command timed out after 30 seconds"
        }

        // Drain remaining data and clean up handlers
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        pipeQueue.sync {
            stderrData.append(remainingStderr)
            stdoutData.append(remainingStdout)
        }

        if process.terminationStatus != 0 {
            let errorString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let outString = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return errorString.isEmpty ? (outString.isEmpty ? "Exit code \(process.terminationStatus)" : outString) : errorString
        }

        return nil
    }
}
