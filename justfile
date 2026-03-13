project := "Claude Status.xcodeproj"
scheme := "Claude Status"
# Override deployment target for CI/older Xcode that doesn't know macOS 26.2
xcode_flags := "CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=15.0"
app_name := "Claude Status"

# Calculate version from git tags: tag + .devN for unreleased commits
version := `tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0"); commits=$(git rev-list --count "$tag"...HEAD 2>/dev/null || echo "0"); if [ "$commits" -gt 0 ]; then echo "$tag.dev$commits"; else echo "$tag"; fi`

# Build the Rust plugin binaries and copy to the plugin scripts directory
build-plugin:
    cd claude-status-plugin && cargo build --release
    mkdir -p claude-status-plugin/plugins/claude-status/scripts
    cp claude-status-plugin/target/release/session-status claude-status-plugin/plugins/claude-status/scripts/
    cp claude-status-plugin/target/release/set-session-name claude-status-plugin/plugins/claude-status/scripts/
    codesign -fs - claude-status-plugin/plugins/claude-status/scripts/session-status
    codesign -fs - claude-status-plugin/plugins/claude-status/scripts/set-session-name

# Build debug configuration
build: build-plugin
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" -configuration Debug build {{xcode_flags}} MARKETING_VERSION="{{version}}"

# Run all unit tests
test:
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" -configuration Debug test \
        -only-testing:"Claude StatusTests" {{xcode_flags}}

# Run a single test class (e.g., just test-class SessionStateTests)
test-class class:
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" \
        -only-testing:"Claude StatusTests/{{class}}" test {{xcode_flags}}

# Clean build artifacts
clean:
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" clean {{xcode_flags}}

# Kill running app, copy debug build to /Applications, and relaunch
swap: build
    #!/usr/bin/env bash
    set -euo pipefail
    derived_data=$(xcodebuild -project "Claude Status.xcodeproj" -scheme "Claude Status" -showBuildSettings 2>/dev/null | grep ' BUILD_DIR ' | awk '{print $3}')
    pkill -x "{{app_name}}" || true
    sleep 0.5
    rm -rf "/Applications/{{app_name}}.app"
    cp -R "${derived_data}/Debug/{{app_name}}.app" "/Applications/{{app_name}}.app"
    open -a "{{app_name}}"

# Show the calculated version
show-version:
    @echo "{{version}}"

# Sync the full plugin to the installed plugin cache and update the registry
sync-plugin: build-plugin
    rm -rf ~/.claude/plugins/cache/claude-status-marketplace/
    mkdir -p ~/.claude/plugins/cache/claude-status-marketplace/claude-status/{{version}}/
    rsync -a claude-status-plugin/plugins/claude-status/ \
        ~/.claude/plugins/cache/claude-status-marketplace/claude-status/{{version}}/
    codesign -fs - ~/.claude/plugins/cache/claude-status-marketplace/claude-status/{{version}}/scripts/session-status
    codesign -fs - ~/.claude/plugins/cache/claude-status-marketplace/claude-status/{{version}}/scripts/set-session-name
    python3 -c "\
    import json, pathlib; \
    p = pathlib.Path.home() / '.claude/plugins/installed_plugins.json'; \
    d = json.loads(p.read_text()); \
    key = 'claude-status@claude-status-marketplace'; \
    ver = '{{version}}'; \
    path = str(pathlib.Path.home() / '.claude/plugins/cache/claude-status-marketplace/claude-status' / ver); \
    entry = d.get('plugins', {}).get(key, [{}])[0]; \
    entry['installPath'] = path; \
    entry['version'] = ver; \
    d.setdefault('plugins', {})[key] = [entry]; \
    p.write_text(json.dumps(d, indent=2) + '\n')"
