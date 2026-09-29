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

WARNING: while Keep Awake is ON, your Mac does not sleep, even with the lid closed.
A closed laptop in a bag or sleeve can get very hot and drain its battery.
Turn it off before you pack the Mac away.

EOF
{ : </dev/tty; } 2>/dev/null || die "No terminal to read your answer from. Run this from Terminal."
read -r -p "Continue? [y/N] " answer </dev/tty
case "$answer" in
    [yY] | [yY][eE][sS]) ;;
    *) echo "Nothing installed."; exit 0 ;;
esac

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

# 4. Start SwiftBar or reload its plugins
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
Click the icon to switch.

Two more things:
  - Turn on "Launch at Login": click the icon, then SwiftBar > Preferences.
    Otherwise the icon is gone after a restart, but the sleep setting can stay on.
  - Allow SwiftBar notifications when macOS asks. The heat warning is shown there
    each time you turn Keep Awake on.

If the icon doesn't appear, check System Settings > Menu Bar and allow SwiftBar.
EOF
