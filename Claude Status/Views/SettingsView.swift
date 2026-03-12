import ServiceManagement
import Sparkle
import SwiftUI

/// Settings window with icon style, launch at login, and plugin management.
struct SettingsView: View {
    var pluginState: PluginInstallState
    var updater: SPUUpdater
    var onInstallPlugin: () -> Void
    var onUninstallPlugin: () -> Void

    @AppStorage("iconStyle", store: UserDefaults(suiteName: "group.com.poisonpenllc.Claude-Status"))
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

            Section("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Updates")
                            .font(.body)
                        Text("Check for updates daily and install automatically")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.switch)
                }
                HStack {
                    Spacer()
                    Button("Check for Updates\u{2026}") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }

            Section("Plugin") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Claude Code Plugin")
                                .font(.body)
                            statusBadge
                        }
                        Text("Reports session activity via Claude Code hooks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    pluginButtons
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch pluginState {
        case .installed:
            Text("Installed")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .notInstalled:
            Text("Not Installed")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .unknown:
            Text("Unknown")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private var pluginButtons: some View {
        switch pluginState {
        case .installed:
            HStack(spacing: 8) {
                Button("Reinstall") { onInstallPlugin() }
                Button("Uninstall") { onUninstallPlugin() }
            }
        case .notInstalled:
            Button("Install") { onInstallPlugin() }
        case .unknown:
            Button("Install") { onInstallPlugin() }
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
