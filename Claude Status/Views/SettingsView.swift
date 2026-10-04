import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

/// Settings window with icon style, launch at login, and profile/plugin management.
struct SettingsView: View {
    @Bindable var profileStore: ProfileStore
    var updater: SPUUpdater?
    var onInstallPlugin: (ClaudeProfile) -> Void
    var onUninstallPlugin: (ClaudeProfile) -> Void

    @AppStorage("iconStyle", store: AppGroup.defaults)
    private var iconStyle: SessionIconStyle = .emoji
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Status Icon Style", selection: $iconStyle) {
                    ForEach(SessionIconStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }

            if let build = BuildInfo.current {
                Section {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    LabeledContent("Source", value: build.source)
                    LabeledContent("Branch", value: build.branch)
                    LabeledContent("Commit") {
                        Text(build.commit).textSelection(.enabled)
                    }
                    LabeledContent("Built", value: build.date)
                } header: {
                    Text("Development Build")
                } footer: {
                    Text("Automatic updates are disabled for local builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let updater {
                Section("Updates") {
                    Toggle(isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Updates")
                                .font(.body)
                            Text("Check for updates daily and install automatically")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    HStack {
                        Spacer()
                        Button("Check for Updates\u{2026}") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    }
                }
            }

            Section {
                ForEach(profileStore.profiles) { profile in
                    ProfileRowView(
                        profile: profile,
                        profileStore: profileStore,
                        onInstallPlugin: onInstallPlugin,
                        onUninstallPlugin: onUninstallPlugin
                    )
                }
                HStack {
                    Text("~/.claude and ~/.claude-* are detected automatically")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Add Folder\u{2026}") { addProfileFolder() }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Each profile is a Claude Code config directory (CLAUDE_CONFIG_DIR). The session-status plugin must be installed per profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addProfileFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = "Choose a Claude Code config directory (CLAUDE_CONFIG_DIR)"
        if panel.runModal() == .OK, let url = panel.url {
            guard ProfileStore.looksLikeProfile(url) else {
                let alert = NSAlert()
                alert.messageText = "Not a Claude Code Config Directory"
                alert.informativeText = "The selected folder has no projects/ directory or settings.json."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
            profileStore.addManualProfile(at: url)
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}

/// One profile row: enable toggle, renameable label, path, plugin status, actions.
private struct ProfileRowView: View {
    let profile: ClaudeProfile
    var profileStore: ProfileStore
    var onInstallPlugin: (ClaudeProfile) -> Void
    var onUninstallPlugin: (ClaudeProfile) -> Void

    @State private var editedName: String = ""
    @State private var pluginState: PluginInstallState = .unknown
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { profile.isEnabled },
                set: { profileStore.setEnabled($0, for: profile) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Monitor sessions from this profile")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Name", text: $editedName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($nameFocused)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { commitName() }
                        }
                        .frame(maxWidth: 140)
                    statusBadge
                }
                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            actionMenu
        }
        .opacity(profile.isEnabled ? 1 : 0.5)
        .onAppear {
            editedName = profile.displayName
            pluginState = PluginDetector(claudeDir: profile.directory).detect()
        }
    }

    private var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = profile.directory.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func commitName() {
        profileStore.setLabel(editedName, for: profile)
        // `profile` is a pre-mutation copy; read the normalized name back from the store
        let updated = profileStore.profiles.first { $0.id == profile.id }
        editedName = (updated ?? profile).displayName
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch pluginState {
        case .installed:
            badge("Plugin Installed", color: .green)
        case .notInstalled:
            badge("No Plugin", color: .orange)
        case .unknown:
            badge("Unknown", color: .secondary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var actionMenu: some View {
        Menu {
            switch pluginState {
            case .installed:
                Button("Reinstall Plugin") { onInstallPlugin(profile) }
                Button("Uninstall Plugin") { onUninstallPlugin(profile) }
            case .notInstalled, .unknown:
                Button("Install Plugin") { onInstallPlugin(profile) }
            }
            if !profile.isAutoDetected {
                Divider()
                Button("Remove Profile", role: .destructive) {
                    profileStore.removeManualProfile(profile)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
