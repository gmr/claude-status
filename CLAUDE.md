# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Status is a native macOS menu bar utility that monitors all active Claude Code sessions on the local machine. It shows session status, project info, and provides one-click focus to the session's host app (terminals and IDEs).

## Build & Test

This is an Xcode project (no SPM Package.swift). Build and test via `xcodebuild`:

```bash
# Build
xcodebuild -project "Claude Status.xcodeproj" -scheme "Claude Status" -configuration Debug build

# Run all tests (unit + UI)
xcodebuild -project "Claude Status.xcodeproj" -scheme "Claude Status" -configuration Debug test

# Run a single test class
xcodebuild -project "Claude Status.xcodeproj" -scheme "Claude Status" -only-testing:"Claude StatusTests/SessionStateTests" test
```

## Architecture

Menu bar-only app (`LSUIElement = YES`, no Dock icon). App Sandbox is disabled — required for process tree inspection (`proc_pidinfo`, `sysctl KERN_PROCARGS2`) and AppleScript automation.

### Targets

| Target | Purpose |
|---|---|
| `Claude Status` | Main app: `NSStatusItem` + `NSPopover` with SwiftUI views |
| `Claude StatusTests` | Unit tests (Swift Testing framework) |
| `Claude StatusUITests` | UI tests |
| `Claude StatusWidgetExtension` | WidgetKit desktop widget |

### Source Layout

- `Claude Status/main.swift` — App entry point, delegates to `AppDelegate`
- `Claude Status/AppDelegate.swift` — `NSStatusItem`, `NSPopover`, settings window, event handling
- `Shared/` — Models shared between the app and widget extension:
  - `ClaudeSession.swift` — `ClaudeSession` model, `SessionState` enum (active/waiting/idle/compacting), `SessionSource` enum
  - `ProductivityStats.swift` — `ProductivityStats` and `ProductivityData` models for time-in-state tracking
- `Claude Status/SessionDiscovery/` — Core session monitoring:
  - `SessionDiscovery.swift` — Scans `~/.claude/projects/*/*.cstatus` files, validates PIDs via `kill(pid, 0)`, classifies session source by walking the process tree
  - `StateResolver.swift` — `DispatchSource` file watcher on `~/.claude/projects/`; fallback JSONL timestamp resolution for sessions without `.cstatus` files
  - `SessionMonitor.swift` — `@Observable` class with three update mechanisms: Darwin notifications (instant), file system watching, and 5s polling timer
  - `ITermFocuser.swift` — `SessionFocuser`: focuses session host app (iTerm2 with session-specific AppleScript, plus Terminal, Warp, Alacritty, Kitty, WezTerm, Ghostty, Xcode, VS Code, JetBrains IDEs, Zed)
  - `PluginDetector.swift` — Checks `~/.claude/plugins/installed_plugins.json` and `~/.claude/settings.json` for plugin/hook installation
  - `PluginInstaller.swift` — Installs/uninstalls the bundled plugin via `claude plugin` CLI commands
- `Claude Status/Views/` — SwiftUI views:
  - `SessionListView.swift` — Popover content: header, session list, empty state, Settings/Quit menu
  - `SessionRowView.swift` — Individual session row with status icon, project name, source, activity, time
  - `SettingsView.swift` — Settings window: icon style picker, launch at login, plugin install/uninstall
- `claude-plugin/` — Bundled Claude Code plugin (marketplace structure with hooks.json and session-status.sh)

### Session Discovery

Sessions are discovered via `.cstatus` files written by the Claude Code plugin hook script. `SessionDiscovery` scans `~/.claude/projects/*/` for `.cstatus` files, parses the JSON (session ID, PID, state, activity, cwd), validates PIDs with `kill(pid, 0)`, and classifies the session source by walking the process tree with `proc_pidinfo`/`proc_pidpath` and reading environment variables via `sysctl KERN_PROCARGS2`.

### Session State

State is reported by the hook script in `.cstatus` files:

| State | Emoji | Dot | Description |
|---|---|---|---|
| Active | ⚡ | 🟢 green | Claude is working (tool use, response streaming) |
| Waiting | ⏳ | 🟠 orange | Needs user input |
| Compacting | 🧹 | 🔵 blue | Context compaction in progress |
| Idle | 💤 | ⚪ gray | No recent activity |

### Update Mechanisms

1. **Darwin notifications** — Hook script posts `com.poisonpenllc.Claude-Status.session-changed` via `notifyutil -p` for instant updates
2. **File system watching** — `DispatchSource` on `~/.claude/projects/` triggers refresh on any file change
3. **Polling timer** — 5s fallback for sessions without hooks (IDE agents, etc.)

## Platform & Language

- **macOS 26.2+** deployment target
- **Swift 5.0** with `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **SwiftUI + AppKit** hybrid (AppKit for `NSStatusItem`/`NSPopover`/`NSWindow`, SwiftUI for views)
- Bundle ID: `com.poisonpenllc.Claude-Status`
- App Group: `group.com.poisonpenllc.Claude-Status`
- URL Scheme: `claude-status://`

## Key Runtime Paths

- `~/.claude/projects/` — Claude Code session state (encoded project paths as directory names)
- `~/.claude/projects/<path>/<session-id>.cstatus` — Session status files written by the hook script
- `~/.claude/projects/<path>/sessions-index.json` — Session index with metadata, prompts, timestamps
- `~/.claude/projects/<path>/<uuid>.jsonl` — Conversation logs per session
- `~/.claude/plugins/installed_plugins.json` — Plugin registry
