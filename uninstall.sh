#!/bin/bash
# Removes Keep Awake: turns normal sleep back on, deletes the sudo rule, the SwiftBar plugin
# and its Claude Code hooks.
# SwiftBar itself stays installed.
set -euo pipefail

PLUGIN_NAME="keep-awake"
SUDOERS_FILE="/etc/sudoers.d/keep-awake"
SWIFTBAR_ID="com.ameba.SwiftBar"
STATE_DIR="$HOME/.keep-awake"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Keep Awake only works on macOS."
[ "$EUID" -ne 0 ] || die "Run this as your normal user, without sudo. It asks for your password when it needs it."

# Leave Auto mode first, so a Claude hook can't turn Keep Awake back on.
rm -rf "$STATE_DIR"

if /usr/bin/pmset -g | grep -Eq '^[[:space:]]*SleepDisabled[[:space:]]+1'; then
    say "Turning normal sleep back on"
    sudo /usr/bin/pmset -a disablesleep 0
fi

if [ -e "$SUDOERS_FILE" ]; then
    say "Removing the sudo rule ($SUDOERS_FILE)"
    sudo rm -f "$SUDOERS_FILE"
fi

plugin_dir=$(defaults read "$SWIFTBAR_ID" PluginDirectory 2>/dev/null || true)
plugin_dir=${plugin_dir/#\~/$HOME}
if [ -n "$plugin_dir" ] && [ -d "$plugin_dir" ]; then
    say "Removing the plugin from $plugin_dir"
    rm -f "$plugin_dir/$PLUGIN_NAME".*.sh
    if /usr/bin/pgrep -x SwiftBar >/dev/null; then
        open -g "swiftbar://refreshallplugins"
    fi
fi

if [ -f "$CLAUDE_SETTINGS" ] && grep -q 'keep-awake\.10s\.sh' "$CLAUDE_SETTINGS"; then
    jq=$(command -v jq || true)
    [ -n "$jq" ] || [ ! -x /usr/bin/jq ] || jq=/usr/bin/jq
    if [ -z "$jq" ]; then
        say "jq was not found. Remove the hooks that run keep-awake.10s.sh from $CLAUDE_SETTINGS by hand."
    else
        say "Removing the Claude Code hooks from $CLAUDE_SETTINGS"
        cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.keep-awake-backup"
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        "$jq" '
            if .hooks then
                .hooks |= (map_values(map(.hooks |= map(select(.command // "" | contains("keep-awake.10s.sh") | not)))
                        | map(select(.hooks | length > 0)))
                    | with_entries(select(.value | length > 0)))
                | if .hooks == {} then del(.hooks) else . end
            else . end
        ' "$CLAUDE_SETTINGS" >"$tmp"
        # cat, not mv: keeps the file's permissions, and a symlink to a dotfiles repo stays a symlink.
        cat "$tmp" >"$CLAUDE_SETTINGS"
    fi
fi

cat <<'EOF'

Keep Awake is removed and your Mac sleeps normally again.
SwiftBar is still installed. If you don't use it for anything else:
  brew uninstall --cask swiftbar
EOF
