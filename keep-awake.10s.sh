#!/bin/bash
# <xbar.title>Keep Awake</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.desc>Turn macOS sleep off and on (pmset disablesleep) from the menu bar.</xbar.desc>
# <xbar.abouturl>https://github.com/slaven-ostojic/mac-keep-awake</xbar.abouturl>
# <swiftbar.runInBash>false</swiftbar.runInBash>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

PMSET=/usr/bin/pmset
REPO_URL=https://github.com/slaven-ostojic/mac-keep-awake
ORANGE='#FF9500'
RED='#FF3B30'

sleep_disabled() { "$PMSET" -g | /usr/bin/grep -Eq '^[[:space:]]*SleepDisabled[[:space:]]+1'; }
on_battery() { "$PMSET" -g batt | /usr/bin/grep -q "'Battery Power'"; }

# swiftbar://notify turns '+' into spaces, so messages stick to letters, digits and . , -
notify() {
    /usr/bin/open -g "swiftbar://notify?plugin=keep-awake&title=${1// /+}&body=${2// /+}"
}

toggle() {
    local target=1
    sleep_disabled && target=0
    if ! /usr/bin/sudo -n "$PMSET" -a disablesleep "$target" 2>/dev/null; then
        notify "Keep Awake could not switch" "The sudo rule is missing. Run install.sh again."
        exit 1
    fi
    if [ "$target" = 1 ]; then
        notify "Keep Awake is ON" "Your Mac will not sleep, even with the lid closed. Do not put it in a bag while this is on, it can overheat."
    fi
}

if [ "${1:-}" = toggle ]; then
    toggle
    exit 0
fi

if sleep_disabled; then
    color=$ORANGE
    on_battery && color=$RED
    echo ":cup.and.saucer.fill: | sfcolor=$color tooltip=\"Keep Awake is ON\""
    echo "---"
    echo "Keep Awake is on. Your Mac won't sleep, even with the lid closed."
    echo "---"
    echo "Allow sleep | bash=\"$0\" param1=toggle terminal=false refresh=true sfimage=moon.zzz"
else
    echo ":moon.zzz: | tooltip=\"Keep Awake is off\""
    echo "---"
    echo "Keep Awake is off. Your Mac sleeps normally."
    echo "---"
    echo "Keep awake | bash=\"$0\" param1=toggle terminal=false refresh=true sfimage=cup.and.saucer.fill"
fi
echo "---"
echo "About Keep Awake | href=$REPO_URL"
