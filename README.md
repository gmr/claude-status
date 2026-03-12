# Claude Status

A native macOS menu bar utility that monitors all active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions on your machine. See what every session is doing at a glance, and jump to any one with a click.

![macOS](https://img.shields.io/badge/macOS-26.2%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/License-BSD_3--Clause-green)

![Claude Status screenshot showing the menu bar dropdown and desktop widget](assets/screenshot.png)

## Features

- **Real-time session monitoring** — Discovers sessions via `.cstatus` files written by a Claude Code plugin hook, with instant Darwin notification updates
- **Menu bar status indicator** — Shows aggregate session state as a colored dot or emoji overlay on the menu bar icon
- **Four session states** — Active (working), Waiting (needs input), Compacting (context compaction), and Idle
- **Multi-app focus** — Click any session in the dropdown or widget to focus its host app (see [Session Focusing](#session-focusing) for details)
- **Two icon styles** — Toggle between emoji indicators (⚡ ⏳ 🧹 💤) and colored status dots
- **Desktop widget** — WidgetKit widget showing session count and status at a glance
- **Custom session names** — Name sessions via the `/name-session` slash command; names persist across status updates and display in the menu bar and widget
- **Settings window** — Icon style, launch at login, plugin install/uninstall
- **Deep linking** — `claude-status://session/<id>` URLs for widget-to-app navigation

## How It Works

### Plugin Hook

Claude Status includes a bundled Claude Code plugin that registers hooks for session lifecycle events. When Claude Code starts, stops, or changes state, the hook script writes a `.cstatus` JSON file to `~/.claude/projects/<encoded-path>/` and posts a Darwin notification for instant UI updates.

### Session Discovery

1. **File scanning** — Enumerates `~/.claude/projects/*/` directories for `.cstatus` files containing session ID, PID, state, activity, and working directory
2. **PID validation** — Confirms each session's process is still alive via `kill(pid, 0)`
3. **Source classification** — Walks the process tree (`proc_pidpath`, `proc_pidinfo`) and reads environment variables (`sysctl KERN_PROCARGS2`) to identify whether a session is running in a terminal or IDE

### Session States

| State          | Emoji | Dot | Description                              |
| -------------- | ----- | --- | ---------------------------------------- |
| **Active**     | ⚡    | 🟢  | Claude is working (tool use, streaming)  |
| **Waiting**    | ⏳    | 🟠  | Needs user input                         |
| **Compacting** | 🧹    | 🔵  | Context compaction in progress           |
| **Idle**       | 💤    | ⚪  | No recent activity                       |

### Menu Bar Indicator

The menu bar icon reflects the aggregate state across all sessions:

- **No sessions** — Plain icon, no indicator
- **Any session active** — Green dot or ⚡ (highest priority)
- **Any session waiting** — Orange dot or ⏳
- **Any compacting** — Blue dot or 🧹
- **All idle** — Gray dot or 💤

### Update Mechanisms

Three complementary mechanisms keep the UI current:

1. **Darwin notifications** — Instant push from the hook script via `notifyutil -p`
2. **File system watching** — `DispatchSource` on `~/.claude/projects/` triggers refresh on file changes
3. **Polling timer** — 5s fallback for sessions without hooks

### Session Naming

The plugin includes a `/name-session` skill that lets you set a custom display name for the current Claude Code session. When set, the session name replaces the project directory name as the primary label in both the menu bar dropdown and the desktop widget, with the project name shown in the subtitle.

```text
/name-session API Refactor
```

The name is stored in the session's `.cstatus` file as a `session_name` field. The hook script carries it forward across status updates automatically. The name persists for the lifetime of the session.

### Session Focusing

Clicking a session in the menu bar dropdown or the desktop widget navigates directly to the session's host app. The behavior varies by app type:

| Host App | Focus Behavior |
| --- | --- |
| **iTerm2** | Activates the specific tab and window containing the session via AppleScript |
| **Terminal, Warp, Alacritty, Kitty, WezTerm, Ghostty** | Activates the terminal app |
| **tmux sessions** | Selects the correct tmux window and pane (unzooming if needed), then activates the hosting terminal. Works with any terminal that runs tmux, and resolves the real terminal app even inside tmux (via `LC_TERMINAL`, `ITERM_SESSION_ID`, `GHOSTTY_RESOURCES_DIR`, etc.) |
| **VS Code** | Activates VS Code (detected via bundled Claude Code extension path or `VSCODE_*` env vars, including inside tmux) |
| **Zed** | Activates Zed (detected via process tree, `TERM_PROGRAM`, or inside tmux) |
| **Xcode** | Activates Xcode (detected via the Coding Assistant executable path) |
| **JetBrains IDEs** | Activates the specific IDE — IntelliJ IDEA, PyCharm, WebStorm, GoLand, CLion, RubyMine, Rider, PhpStorm, DataGrip, or DataSpell (detected via `TERMINAL_EMULATOR` and `__CFBundleIdentifier` env vars) |

The desktop widget uses `claude-status://session/<id>` deep links, which open the main app and trigger the same focus logic.

## Installation

### Build from Source

```bash
git clone https://github.com/gmr/claude-status.git
cd claude-status
xcodebuild -project "Claude Status.xcodeproj" \
  -scheme "Claude Status" \
  -configuration Release build
```

The built app will be in `build/Release/Claude Status.app`. Move it to `/Applications`.

On first launch, the app will prompt to install the Claude Code plugin. You can also install or uninstall it later from Settings.

### Requirements

- **macOS 26.2** or later
- **Xcode 26** or later (to build from source)
- **Claude Code** CLI installed (`~/.local/bin/claude`)

## Usage

- **Left-click** the menu bar icon to open the session popover
- **Right-click** for a quick context menu (Refresh, Quit)
- **Click a session** to [focus it](#session-focusing) in its host app (terminal, IDE, or tmux pane)
- **Hover a session** to see its full working directory path

## Architecture

```
Claude Status/
├── main.swift                    # App entry point
├── AppDelegate.swift             # Menu bar, popover, settings window, deep links
├── SessionDiscovery/
│   ├── ClaudeSession.swift       # Session model, SessionState, SessionSource enums
│   ├── SessionDiscovery.swift    # .cstatus file scanning, PID validation, source classification
│   ├── StateResolver.swift       # File system watcher, fallback JSONL state resolution
│   ├── SessionMonitor.swift      # Observable monitor: Darwin notifications + FS watch + polling
│   ├── ITermFocuser.swift        # SessionFocuser: multi-app focus (terminals + IDEs)
│   ├── PluginDetector.swift      # Detects plugin/hook installation state
│   └── PluginInstaller.swift     # Installs/uninstalls plugin via claude CLI
├── Views/
│   ├── SessionListView.swift     # Popover UI: header, session list, menu
│   ├── SessionRowView.swift      # Session row with status, project, activity, time
│   └── SettingsView.swift        # Settings: icon style, launch at login, plugin management
├── claude-plugin/                # Bundled Claude Code plugin (hooks + marketplace)
└── Claude StatusWidget/          # WidgetKit desktop widget
```

### Key Design Decisions

- **Menu bar-only app** (`LSUIElement = YES`) — No dock icon, no main window
- **App Sandbox disabled** — Required for process tree inspection and AppleScript automation
- **AppKit + SwiftUI hybrid** — AppKit for `NSStatusItem`/`NSPopover`/`NSWindow`, SwiftUI for all views
- **File-driven discovery** — Sessions discovered via `.cstatus` files, not process table scanning
- **Three-tier update strategy** — Darwin notifications for instant updates, file watching for backup, polling as fallback

### Targets

| Target                         | Purpose                    |
| ------------------------------ | -------------------------- |
| `Claude Status`                | Main menu bar app          |
| `Claude StatusTests`           | Unit tests (Swift Testing) |
| `Claude StatusUITests`         | UI tests                   |
| `Claude StatusWidgetExtension` | WidgetKit desktop widget   |

## Key Runtime Paths

| Path                                                    | Purpose                               |
| ------------------------------------------------------- | ------------------------------------- |
| `~/.claude/projects/`                                   | Claude Code session state directories |
| `~/.claude/projects/<encoded-path>/<session-id>.cstatus`| Session status files from hook script |
| `~/.claude/projects/<encoded-path>/<uuid>.jsonl`        | Conversation logs per session         |
| `~/.claude/projects/<encoded-path>/sessions-index.json` | Session metadata index                |
| `~/.claude/plugins/installed_plugins.json`              | Plugin registry                       |

## Testing

```bash
# Run all tests
xcodebuild -project "Claude Status.xcodeproj" \
  -scheme "Claude Status" -configuration Debug test

# Run a specific test class
xcodebuild -project "Claude Status.xcodeproj" \
  -scheme "Claude Status" \
  -only-testing:"Claude StatusTests/SessionStateTests" test
```

## License

[BSD 3-Clause License](LICENSE)
