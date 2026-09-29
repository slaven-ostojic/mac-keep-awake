#!/bin/bash
# <xbar.title>Keep Awake</xbar.title>
# <xbar.version>v1.1</xbar.version>
# <xbar.desc>Turn macOS sleep off and on (pmset disablesleep) from the menu bar, by hand or automatically while Claude Code works.</xbar.desc>
# <xbar.abouturl>https://github.com/slaven-ostojic/mac-keep-awake</xbar.abouturl>
# <swiftbar.runInBash>false</swiftbar.runInBash>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

PMSET=/usr/bin/pmset
REPO_URL=https://github.com/slaven-ostojic/mac-keep-awake
ORANGE='#FF9500'
RED='#FF3B30'

# Auto mode: while this file exists, Claude Code hooks decide the sleep setting.
STATE_DIR="$HOME/.keep-awake"
AUTO_FLAG="$STATE_DIR/auto"
# One file per working Claude session, holding the PID of its claude process.
HOLDS_DIR="$STATE_DIR/claude"
# A hold not refreshed for this long is dropped, in case its session never sent a release.
HOLD_MAX_MINUTES=180
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

sleep_disabled() { "$PMSET" -g | /usr/bin/grep -Eq '^[[:space:]]*SleepDisabled[[:space:]]+1'; }
on_battery() { "$PMSET" -g batt | /usr/bin/grep -q "'Battery Power'"; }
lid_closed() { /usr/sbin/ioreg -r -k AppleClamshellState -d 1 | /usr/bin/grep -q '"AppleClamshellState" = Yes'; }
auto_mode() { [ -e "$AUTO_FLAG" ]; }
hooks_installed() { [ -f "$CLAUDE_SETTINGS" ] && /usr/bin/grep -q 'keep-awake\.10s\.sh.*claude-hold' "$CLAUDE_SETTINGS"; }

# swiftbar://notify turns '+' into spaces, so messages stick to letters, digits and . , -
notify() {
    /usr/bin/open -g "swiftbar://notify?plugin=keep-awake&title=${1// /+}&body=${2// /+}"
}

set_sleep_disabled() {
    if ! /usr/bin/sudo -n "$PMSET" -a disablesleep "$1" 2>/dev/null; then
        notify "Keep Awake could not switch" "The sudo rule is missing. Run install.sh again."
        return 1
    fi
}

set_mode() {
    /bin/mkdir -p "$STATE_DIR"
    case "$1" in
        off)
            /bin/rm -rf "$AUTO_FLAG" "$HOLDS_DIR"
            set_sleep_disabled 0
            ;;
        on)
            /bin/rm -rf "$AUTO_FLAG" "$HOLDS_DIR"
            set_sleep_disabled 1 &&
                notify "Keep Awake is ON" "Your Mac will not sleep, even with the lid closed. Do not put it in a bag while this is on, it can overheat."
            ;;
        auto)
            /usr/bin/touch "$AUTO_FLAG"
            reconcile
            notify "Keep Awake is on Auto" "Your Mac stays awake while Claude Code works, even with the lid closed, and sleeps normally otherwise."
            ;;
    esac
}

# The claude process that ran the hook: the first ancestor that isn't a shell.
claude_pid() {
    local pid=$PPID comm _
    for _ in 1 2 3 4 5; do
        comm=$(/bin/ps -o comm= -p "$pid" 2>/dev/null) || break
        comm=${comm##*/}
        case "${comm#-}" in
            sh | bash | zsh | dash) pid=$(/bin/ps -o ppid= -p "$pid" | /usr/bin/tr -d ' ') ;;
            *) echo "$pid"; return ;;
        esac
    done
    echo "$PPID"
}

# Claude Code hooks call this with the hook's JSON on stdin. It must print nothing:
# a UserPromptSubmit hook's output goes into Claude's context.
claude_hook() {
    local action=$1 input session
    input=$(/bin/cat)
    auto_mode || return 0
    session=$(echo "$input" | /usr/bin/grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | /usr/bin/sed 's/.*"\([^"]*\)"$/\1/' | /usr/bin/tr -cd 'A-Za-z0-9_-')
    [ -n "$session" ] || return 0
    # Stop lists background tasks still running. Claude wakes up again when they finish, so keep holding.
    if [ "$action" = release ] && echo "$input" | /usr/bin/grep -q '"background_tasks"[[:space:]]*:[[:space:]]*\[[[:space:]]*[^][:space:]]'; then
        action=hold
    fi
    /bin/mkdir -p "$HOLDS_DIR"
    if [ "$action" = hold ]; then
        claude_pid >"$HOLDS_DIR/$session"
    else
        /bin/rm -f "$HOLDS_DIR/$session"
    fi
    reconcile
}

# Makes the sleep setting match the holds. Serialized, so a hold and a release racing
# each other can't leave the setting wrong.
reconcile() {
    /bin/mkdir -p "$STATE_DIR"
    /usr/bin/lockf -t 10 "$STATE_DIR/.lock" "$0" reconcile-locked
}

reconcile_locked() {
    auto_mode || return 0
    local hold pid want=0
    for hold in "$HOLDS_DIR"/*; do
        [ -f "$hold" ] || continue
        pid=$(/bin/cat "$hold" 2>/dev/null)
        if [ -z "$pid" ] || ! /bin/kill -0 "$pid" 2>/dev/null ||
            [ -n "$(/usr/bin/find "$hold" -mmin +"$HOLD_MAX_MINUTES")" ]; then
            /bin/rm -f "$hold"
        else
            want=1
        fi
    done
    if [ "$want" = 1 ]; then
        sleep_disabled || set_sleep_disabled 1
    elif sleep_disabled; then
        set_sleep_disabled 0 || return
        # If the lid was closed while sleep was off, nothing else puts the Mac to sleep now.
        # Plugged in, it may be driving an external display, so only do this on battery.
        if lid_closed && on_battery; then
            "$PMSET" sleepnow >/dev/null 2>&1
        fi
    fi
}

hold_count() {
    local n=0 hold
    for hold in "$HOLDS_DIR"/*; do
        [ -f "$hold" ] && n=$((n + 1))
    done
    echo "$n"
}

case "${1:-}" in
    set) set_mode "${2:-}"; exit 0 ;;
    claude-hold) claude_hook hold >/dev/null 2>&1; exit 0 ;;
    claude-release) claude_hook release >/dev/null 2>&1; exit 0 ;;
    reconcile-locked) reconcile_locked; exit 0 ;;
esac

# Each refresh also drops holds of sessions that ended without a release.
auto_mode && reconcile

tag=""
auto_mode && tag=" A"
if sleep_disabled; then
    color=$ORANGE
    on_battery && color=$RED
    echo ":cup.and.saucer.fill:$tag | sfcolor=$color tooltip=\"Keep Awake is ON\""
else
    echo ":moon.zzz:$tag | tooltip=\"Keep Awake is off\""
fi
echo "---"
if auto_mode; then
    count=$(hold_count)
    if [ "$count" = 0 ]; then
        echo "Auto: Claude isn't working. Your Mac sleeps normally."
    elif [ "$count" = 1 ]; then
        echo "Auto: Claude is working. Your Mac won't sleep, even with the lid closed."
    else
        echo "Auto: $count Claude sessions are working. Your Mac won't sleep, even with the lid closed."
    fi
    hooks_installed || echo "Claude Code hooks are missing. Run install.sh again. | color=$RED"
elif sleep_disabled; then
    echo "Keep Awake is on. Your Mac won't sleep, even with the lid closed."
else
    echo "Keep Awake is off. Your Mac sleeps normally."
fi
echo "---"
off=false on=false auto=false
if auto_mode; then auto=true; elif sleep_disabled; then on=true; else off=true; fi
echo "Off: sleep normally | bash=\"$0\" param1=set param2=off terminal=false refresh=true checked=$off"
echo "On: keep awake | bash=\"$0\" param1=set param2=on terminal=false refresh=true checked=$on"
echo "Auto: keep awake while Claude works | bash=\"$0\" param1=set param2=auto terminal=false refresh=true checked=$auto"
echo "---"
echo "About Keep Awake | href=$REPO_URL"
