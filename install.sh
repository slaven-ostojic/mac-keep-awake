#!/bin/bash
# Installs Keep Awake: a SwiftBar menu bar toggle for `pmset disablesleep`.
# Run it from a clone (./install.sh) or straight from GitHub (curl ... | bash).
set -euo pipefail

REPO_URL="https://github.com/slaven-ostojic/mac-keep-awake"
REPO_RAW_URL="https://raw.githubusercontent.com/slaven-ostojic/mac-keep-awake/main"
PLUGIN_NAME="keep-awake"
PLUGIN_FILE="$PLUGIN_NAME.10s.sh"
SUDOERS_FILE="/etc/sudoers.d/keep-awake"
SWIFTBAR_ID="com.ameba.SwiftBar"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
# Not ~/Library/Application Support/SwiftBar/Plugins: SwiftBar keeps its own per-plugin data there.
DEFAULT_PLUGIN_DIR="$HOME/.swiftbar"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

find_swiftbar() {
    local path
    for path in /Applications/SwiftBar.app "$HOME/Applications/SwiftBar.app"; do
        if [ -d "$path" ]; then
            echo "$path"
            return
        fi
    done
    /usr/bin/mdfind "kMDItemCFBundleIdentifier == '$SWIFTBAR_ID'" 2>/dev/null | /usr/bin/head -1
}

find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
    elif [ -x /opt/homebrew/bin/brew ]; then
        echo /opt/homebrew/bin/brew
    elif [ -x /usr/local/bin/brew ]; then
        echo /usr/local/bin/brew
    fi
}

swiftbar_running() { /usr/bin/pgrep -x SwiftBar >/dev/null; }

ask() {
    local answer
    read -r -p "$1 [y/N] " answer </dev/tty
    case "$answer" in
        [yY] | [yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

find_jq() {
    if command -v jq >/dev/null 2>&1; then
        command -v jq
    elif [ -x /usr/bin/jq ]; then
        echo /usr/bin/jq
    fi
}

# The hooks for Auto mode, as a settings.json "hooks" object. $1 is the installed plugin.
claude_hooks_json() {
    local hold release
    hold=$(printf '"%s" claude-hold' "$1")
    release=$(printf '"%s" claude-release' "$1")
    "$jq" -n --arg hold "$hold" --arg release "$release" '
        def run($cmd): [{hooks: [{type: "command", command: $cmd, timeout: 10}]}];
        {
            UserPromptSubmit: run($hold),
            PreToolUse: run($hold),
            PostToolUse: run($hold),
            Stop: run($release),
            StopFailure: run($release),
            SessionEnd: run($release),
            Notification: [{
                matcher: "idle_prompt",
                hooks: [{type: "command", command: $release, timeout: 10}]
            }]
        }'
}

[ "$(uname -s)" = Darwin ] || die "Keep Awake only works on macOS."
[ "$EUID" -ne 0 ] || die "Run this as your normal user, without sudo. It asks for your password when it needs it."
macos_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$macos_major" -ge 12 ] || die "SwiftBar needs macOS 12 or later."

cat <<'EOF'

Keep Awake adds a menu bar icon that switches macOS sleep off and on
(sudo pmset -a disablesleep 1 / 0).

This script will:
  1. Install SwiftBar, the menu bar app that shows the icon (with Homebrew, if it's missing)
  2. Put the Keep Awake plugin in SwiftBar's plugin folder
  3. Add a sudo rule that lets you run exactly those two pmset commands
     without a password: /etc/sudoers.d/keep-awake
  4. If you use Claude Code, and only if you say yes: add hooks to
     ~/.claude/settings.json for Auto mode, which keeps the Mac awake
     only while Claude is working

WARNING: while Keep Awake is ON, your Mac does not sleep, even with the lid closed.
A closed laptop in a bag or sleeve can get very hot and drain its battery.
Turn it off before you pack the Mac away.

EOF
{ : </dev/tty; } 2>/dev/null || die "No terminal to read your answer from. Run this from Terminal."
ask "Continue?" || { echo "Nothing installed."; exit 0; }

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# 1. SwiftBar
swiftbar_app=$(find_swiftbar)
if [ -z "$swiftbar_app" ]; then
    brew=$(find_brew)
    [ -n "$brew" ] || die "SwiftBar is not installed and Homebrew was not found.
Install SwiftBar from https://swiftbar.app, then run this script again."
    say "Installing SwiftBar with Homebrew"
    "$brew" install --cask swiftbar
    swiftbar_app=$(find_swiftbar)
    [ -n "$swiftbar_app" ] || die "Homebrew finished but SwiftBar.app was not found."
fi
say "SwiftBar: $swiftbar_app"

# 2. Plugin
plugin_dir=$(defaults read "$SWIFTBAR_ID" PluginDirectory 2>/dev/null || true)
plugin_dir=${plugin_dir/#\~/$HOME}
if [ -z "$plugin_dir" ] || [ ! -d "$plugin_dir" ]; then
    plugin_dir=$DEFAULT_PLUGIN_DIR
    mkdir -p "$plugin_dir"
    # SwiftBar reads the plugin folder setting only at launch.
    if swiftbar_running; then
        /usr/bin/pkill -x SwiftBar || true
        for _ in $(seq 50); do
            swiftbar_running || break
            sleep 0.2
        done
    fi
    defaults write "$SWIFTBAR_ID" PluginDirectory "$plugin_dir"
fi
say "Plugin folder: $plugin_dir"

script_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/$PLUGIN_FILE" ]; then
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
if [ -n "$script_dir" ]; then
    cp "$script_dir/$PLUGIN_FILE" "$work_dir/$PLUGIN_FILE"
else
    say "Downloading the plugin from $REPO_URL"
    curl -fsSL "$REPO_RAW_URL/$PLUGIN_FILE" -o "$work_dir/$PLUGIN_FILE"
fi
# Copies with a different refresh interval in the name would show a second icon.
rm -f "$plugin_dir/$PLUGIN_NAME".*.sh
install -m 755 "$work_dir/$PLUGIN_FILE" "$plugin_dir/$PLUGIN_FILE"

# 3. sudo rule
user=$(id -un)
cat >"$work_dir/sudoers" <<EOF
# Added by Keep Awake ($REPO_URL). Remove it with the repo's uninstall.sh.
$user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
EOF
# A broken file in /etc/sudoers.d stops sudo from working at all, so check it before it goes there.
/usr/sbin/visudo -cf "$work_dir/sudoers" >/dev/null || die "The generated sudo rule failed validation. Nothing was added to /etc/sudoers.d."
say "Adding the sudo rule (enter your Mac password if asked)"
sudo /usr/bin/install -m 0440 -o root -g wheel "$work_dir/sudoers" "$SUDOERS_FILE"

# Re-applying the current value is a no-op, so this proves the rule works without changing anything.
current=$(/usr/bin/pmset -g | awk '$1 == "SleepDisabled" { print $2 }')
sudo -k
sudo -n /usr/bin/pmset -a disablesleep "${current:-0}" 2>/dev/null ||
    die "The sudo rule was added but is not active. Check that /etc/sudoers contains '#includedir /private/etc/sudoers.d'."
say "sudo rule works"

# 4. Claude Code hooks for Auto mode
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
    echo
    echo "Auto mode keeps your Mac awake while Claude Code is working and lets it sleep"
    echo "when Claude is done or waiting for you. It needs hooks in $CLAUDE_SETTINGS."
    if ask "Add the Claude Code hooks?"; then
        jq=$(find_jq)
        if [ -z "$jq" ]; then
            say "Skipping the hooks: they need jq, which comes with macOS 15 and later. Run 'brew install jq', then install.sh again."
        else
            mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
            [ -s "$CLAUDE_SETTINGS" ] || echo '{}' >"$CLAUDE_SETTINGS"
            cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.keep-awake-backup"
            # Drops earlier Keep Awake hooks first, so running install.sh again doesn't add them twice.
            if "$jq" --argjson ours "$(claude_hooks_json "$plugin_dir/$PLUGIN_FILE")" '
                (.hooks // {}) as $hooks
                | .hooks = ($hooks
                    | map_values(map(.hooks |= map(select(.command // "" | contains("keep-awake.10s.sh") | not)))
                        | map(select(.hooks | length > 0)))
                    | with_entries(select(.value | length > 0)))
                | reduce ($ours | to_entries[]) as $e (.; .hooks[$e.key] += $e.value)
            ' "$CLAUDE_SETTINGS" >"$work_dir/settings.json"; then
                # cat, not mv: keeps the file's permissions, and a symlink to a dotfiles repo stays a symlink.
                cat "$work_dir/settings.json" >"$CLAUDE_SETTINGS"
                say "Claude Code hooks added (backup: $CLAUDE_SETTINGS.keep-awake-backup)"
            else
                say "Could not read $CLAUDE_SETTINGS as JSON, so the hooks were not added"
            fi
        fi
    fi
fi

# 5. Start SwiftBar or reload its plugins
if swiftbar_running; then
    open -g "swiftbar://refreshallplugins"
else
    open -a "$swiftbar_app"
fi

cat <<'EOF'

Done. The Keep Awake icon is in the menu bar, top right:
  moon          sleep is normal
  orange cup    Keep Awake is ON: the Mac won't sleep, even with the lid closed
  red cup       Keep Awake is ON and the Mac is running on battery
  ... A         the same, in Auto mode: Claude Code decides
Click the icon to pick Off, On or Auto.

Two more things:
  - Turn on "Launch at Login": click the icon, then SwiftBar > Preferences.
    Otherwise the icon is gone after a restart, but the sleep setting can stay on.
  - Allow SwiftBar notifications when macOS asks. The heat warning is shown there
    each time you turn Keep Awake on.

If the icon doesn't appear, check System Settings > Menu Bar and allow SwiftBar.
EOF
