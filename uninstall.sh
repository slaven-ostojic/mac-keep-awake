#!/bin/bash
# Removes Keep Awake: turns normal sleep back on, deletes the sudo rule and the SwiftBar plugin.
# SwiftBar itself stays installed.
set -euo pipefail

PLUGIN_NAME="keep-awake"
SUDOERS_FILE="/etc/sudoers.d/keep-awake"
SWIFTBAR_ID="com.ameba.SwiftBar"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Keep Awake only works on macOS."
[ "$EUID" -ne 0 ] || die "Run this as your normal user, without sudo. It asks for your password when it needs it."

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

cat <<'EOF'

Keep Awake is removed and your Mac sleeps normally again.
SwiftBar is still installed. If you don't use it for anything else:
  brew uninstall --cask swiftbar
EOF
