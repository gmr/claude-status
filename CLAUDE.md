# CLAUDE.md

## Project Overview

Claude Status is a native macOS menu bar app that monitors active Claude Code sessions on the local machine. It shows session state, project info, and provides one-click focus to the session's host app (terminals and IDEs). Distributed outside the Mac App Store via Developer ID signing, notarization, and Sparkle auto-updates.

## Build & Test

Xcode project with SPM dependencies (no standalone Package.swift). Use `just` for all build and test commands:

```bash
just build          # Build debug configuration (includes plugin binaries)
just test           # Run all unit tests
just test-class SessionStateTests  # Run a single test class
just clean          # Clean build artifacts
just swap           # Build, copy to /Applications, and relaunch
just sync-plugin    # Sync plugin to installed plugin cache
just show-version   # Show calculated version from git tags
```

The justfile handles `MACOSX_DEPLOYMENT_TARGET=15.0` override (needed for Xcode versions that don't know about macOS 26.2) and disables code signing for local dev builds.

## Platform & Language

- **macOS 26.2+** deployment target (override to 15.0 for CI/older Xcode)
- **Swift 5.0** with `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **SwiftUI + AppKit** hybrid: AppKit for `NSStatusItem`/`NSPopover`/`NSWindow`, SwiftUI for all views
- **Menu bar-only**: `LSUIElement = YES` (no Dock icon)
- **No App Sandbox**: required for `proc_pidinfo`, `sysctl KERN_PROCARGS2`, and AppleScript automation
- Bundle ID: `com.poisonpenllc.Claude-Status`
- Widget Bundle ID: `com.poisonpenllc.Claude-Status.widget`
- App Group: `group.com.poisonpenllc.Claude-Status` (shared data between app and widget)
- URL Scheme: `claude-status://`

## Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| Sparkle | 2.9.0 | Auto-updates via Appcast (EdDSA-signed) |
| CocoaLumberjack | 3.9.0 | Structured logging |
| swift-log | 1.10.1 | Swift logging API |

## Architecture

### Targets

| Target | Bundle ID | Purpose |
|--------|-----------|---------|
| `Claude Status` | `com.poisonpenllc.Claude-Status` | Main app: `NSStatusItem` + `NSPopover` with SwiftUI views |
| `Claude StatusTests` | `com.poisonpenllc.Claude-StatusTests` | Unit tests (Swift Testing framework) |
| `Claude StatusWidgetExtension` | `com.poisonpenllc.Claude-Status.widget` | WidgetKit desktop widgets (status, productivity, score) |

### Source Layout

```
Claude Status/                         # Main app target
  AppMain.swift                        # Entry point, menu bar-only setup
  AppDelegate.swift                    # NSStatusItem, NSPopover, settings window, Sparkle updater
  Claude_StatusWidgetConfiguration.swift  # WidgetKit configuration
  Info.plist                           # Sparkle feed URL, URL scheme
  Claude Status.entitlements           # App Groups (no sandbox)
  SessionDiscovery/                    # Core session monitoring
    ClaudeProfile.swift                # ClaudeProfile model + ProfileStore (multi-profile config dirs)
    SessionDiscovery.swift             # Scans each profile's projects/*/*.cstatus, validates PIDs, classifies source
    SessionMonitor.swift               # @Observable class: Darwin notifications + file watching + 5s polling
    StateResolver.swift                # DispatchSource file watchers (one per profile); JSONL timestamp fallback
    TerminalFocuser.swift              # SessionFocuser: focuses host app (AppleScript for iTerm2/Ghostty, process activation for others)
    VSCodeSessionLocator.swift         # Finds the VS Code window of an extension session (extension host log dir)
    VSCodeURITrust.swift               # Reads/adds the Claude Code extension in VS Code's trusted URI handlers setting
    ProductivityTracker.swift          # Time-in-state tracking, concurrency, score (persists to App Group)
    PluginDetector.swift               # Checks installed_plugins.json and settings.json for hook status
    PluginInstaller.swift              # Installs/uninstalls bundled plugin via `claude plugin` CLI
  Views/                               # SwiftUI views
    SessionListView.swift              # Popover: header, session list, empty state, Settings/Quit
    SessionRowView.swift               # Session row: status icon, project, source, activity, time
    SettingsView.swift                 # Icon style picker, launch at login, plugin management
    ProductivityBarView.swift          # Visual productivity tracking bar

Shared/                                # Models shared between app and widget
  ClaudeSession.swift                  # ClaudeSession model, SessionState enum, SessionSource enum
  ProductivityStats.swift              # ProductivityStats and ProductivityData models

Claude StatusWidget/                   # Widget extension target
  Claude_StatusWidget.swift            # Widget bundle (3 widgets)
  Claude_StatusTimelineProvider.swift   # WidgetKit timeline provider
  Claude_StatusWidgetEntryView.swift   # Session status widget view
  ProductivityWidget.swift             # Productivity widget definition
  ProductivityWidgetView.swift         # Productivity widget view
  ScoreWidgetView.swift                # Score visualization widget view
  Info.plist                           # Extension metadata
  Claude StatusWidgetExtension.entitlements  # App Sandbox + App Groups

Claude StatusTests/                    # Unit tests
  Claude_StatusTests.swift

claude-plugin/                         # Bundled Claude Code plugin
  plugins/claude-status/
    hooks/hooks.json                   # 14 hook events (SessionStart, Stop, PreToolUse, etc.)
    scripts/
      session-status.py                # Writes .cstatus JSON, posts Darwin notification
      set-session-name.py              # Sets custom session name in .cstatus
    skills/session-name/SKILL.md       # /name-session slash command
    .claude-plugin/plugin.json         # Plugin metadata
  .claude-plugin/marketplace.json      # Marketplace definition
  tests/test_session_status.py         # Python unittest suite for hook script

assets/                                # Marketing assets (screenshot, icons)
```

### Profiles

The app supports multiple Claude Code profiles (config dirs selected via `CLAUDE_CONFIG_DIR`). `ProfileStore` auto-detects `~/.claude` (the "default" profile) and `~/.claude-*` directories (validated by a `projects/` dir or `settings.json`); custom locations can be added manually in Settings. Each profile can be enabled/disabled and renamed; settings persist in the App Group defaults under `claudeProfiles`. Discovery, file watching, and plugin detection/installation all operate per enabled profile (the installer passes `CLAUDE_CONFIG_DIR` to the `claude` CLI). The hook plugin needs no profile awareness — it writes `.cstatus` next to the transcript path Claude Code provides, which already lives in the profile's `projects/` dir.

### Session Discovery Pipeline

1. **Plugin hook** (`session-status`) fires on Claude Code lifecycle events and writes `.cstatus` JSON to `<profile>/projects/<encoded-path>/<session-id>.cstatus`
2. **SessionDiscovery** scans each enabled profile's `projects/*/` for `.cstatus` files, parses JSON (session ID, PID, state, activity, cwd), validates PIDs with `kill(pid, 0)`
3. **Source classification** walks the process tree via `proc_pidinfo`/`proc_pidpath` and reads environment variables via `sysctl KERN_PROCARGS2` to identify the host app
4. **SessionMonitor** (`@Observable`) maintains the session list with three update mechanisms:
   - **Darwin notifications** (instant) — hook posts `com.poisonpenllc.Claude-Status.session-changed` via `notifyutil -p`
   - **File system watching** (fast) — `DispatchSource` on each enabled profile's `projects/` dir
   - **Polling timer** (5s fallback) — catches sessions without hooks (IDE agents)

### Session State

State is reported by the hook script in `.cstatus` files:

| State | Emoji | Dot | Description |
|-------|-------|-----|-------------|
| Active | lightning | green | Claude is working (tool use, response streaming) |
| Waiting | hourglass | orange | Needs user input |
| Compacting | broom | blue | Context compaction in progress |
| Idle | sleep | gray | No recent activity |

### Host App Recognition

**Terminals** (via process tree): iTerm2 (session-specific AppleScript focusing), Terminal, Warp, Alacritty, Kitty, WezTerm, Ghostty

**IDEs** (via process tree): Xcode, VS Code, JetBrains IDEs, Zed

VS Code sessions run by the Claude Code extension are revealed in their own window and tab:
`claude`'s parent is the window's extension host, whose open log files sit under
`logs/<launch>/window<N>/exthost/`. The app opens `vscode://anthropic.claude-code/open?windowId=<N>&session=<id>`;
VS Code routes it to window N and the extension reveals the session's existing tab. Without a window ID the
extension would resume the session in a new tab of the last active window, so the app then only activates VS Code
(also the behavior for `claude` in the integrated terminal).

VS Code confirms URIs aimed at an untrusted extension, and shows that dialog in the target window *before* raising it,
so the click looks like a no-op. On the first click the app checks `extensions.confirmedUriHandlerExtensionIds` in
`~/Library/Application Support/Code/User/settings.json` and, if `anthropic.claude-code` is missing, offers to add it
(in-place text edit that keeps the file's formatting). Declining with "Don't ask again" sets `vscodeTrustPromptDeclined`
in the app's defaults and keeps the plain VS Code activation.

### Productivity Tracking

`ProductivityTracker` maintains daily and all-time stats in the App Group shared container (`productivity.json`), tracking time-in-state across concurrent sessions and calculating a score (0-100). Both the app and widget extension read this shared file.

## Key Runtime Paths

| Path | Purpose |
|------|---------|
| `~/.claude/projects/` | Claude Code session state (encoded project paths as directory names) |
| `~/.claude-<name>/` | Additional Claude Code profiles (`CLAUDE_CONFIG_DIR`), auto-detected |
| `~/.claude/projects/<path>/<session-id>.cstatus` | Session status files written by hook script |
| `~/.claude/projects/<path>/sessions-index.json` | Session index with metadata, prompts, timestamps |
| `~/.claude/projects/<path>/<uuid>.jsonl` | Conversation logs per session |
| `~/.claude/plugins/installed_plugins.json` | Plugin registry |
| `~/Library/Group Containers/group.com.poisonpenllc.Claude-Status/productivity.json` | Shared productivity data |

## CI/CD

### CI Build (`xcode.yml`)

Runs on push/PR to `main`. Two parallel jobs:
- **Build**: `xcodebuild clean build` with code signing disabled
- **Test**: `xcodebuild test` for `Claude StatusTests` only

Both override `MACOSX_DEPLOYMENT_TARGET=15.0`.

### Release (`release.yml`)

Triggered by publishing a GitHub release. The release tag becomes `MARKETING_VERSION`.

**Build & Notarize job:**
1. Import Developer ID certificate from `CERTIFICATE_P12` secret into a temporary keychain
2. Install provisioning profiles (`PROVISIONING_PROFILE_APP`, `PROVISIONING_PROFILE_WIDGET`) — required for App Groups entitlement
3. Inject per-target `PROVISIONING_PROFILE_SPECIFIER` into the pbxproj (Ruby script patches by bundle ID)
4. `xcodebuild archive` with manual signing, hardened runtime
5. `xcodebuild -exportArchive` with `ExportOptions.plist` mapping each bundle ID to its provisioning profile
6. Notarize the `.app` and `.pkg` via `notarytool` (fetches Apple log on failure)
7. Upload `.zip` and `.pkg` as release assets

**Update Appcast job:**
1. Downloads Sparkle tools, generates `appcast.xml` with EdDSA signature
2. Commits to `gh-pages` branch for GitHub Pages hosting

### Release Secrets

| Secret | Purpose |
|--------|---------|
| `CERTIFICATE_P12` | Base64 Developer ID Application certificate |
| `CERTIFICATE_PASSWORD` | P12 password |
| `CODE_SIGN_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `DEVELOPMENT_TEAM` | Apple team ID |
| `PROVISIONING_PROFILE_APP` | Base64 provisioning profile for main app (with App Groups) |
| `PROVISIONING_PROFILE_WIDGET` | Base64 provisioning profile for widget (with App Groups) |
| `INSTALLER_SIGN_IDENTITY` | Developer ID Installer identity for `.pkg` |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for notarization |
| `SPARKLE_ED_PUBLIC_KEY` | EdDSA public key embedded in builds |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for signing appcast |
