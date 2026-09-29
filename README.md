# Keep Awake

A menu bar icon for macOS that stops your Mac from sleeping, **including with the lid closed**, and shows you at a glance whether that's on.

Pick one of three modes from the menu:

| Mode | What it does |
|---|---|
| **Off** | Normal sleep: `sudo pmset -a disablesleep 0` |
| **On** | The Mac never sleeps: `sudo pmset -a disablesleep 1` |
| **Auto** | The Mac stays awake only while [Claude Code](https://claude.com/claude-code) is working, and sleeps normally once Claude is done or waiting for you. See [Auto mode](#auto-mode-claude-code). |

> [!WARNING]
> **Heat.** While Keep Awake is ON, a closed MacBook keeps running. In a bag, a sleeve or under a pillow it can get very hot and drain the battery to zero.
> Turn it off before you pack the Mac away. The icon turns red when Keep Awake is ON and the Mac is on battery, and a notification warns you each time you turn it on.

## What you see

| Icon | Meaning |
|---|---|
| Moon | Keep Awake is off. The Mac sleeps normally. |
| Orange cup | Keep Awake is ON and the Mac is plugged in. |
| Red cup | Keep Awake is ON and the Mac is on battery. |
| Any of these with an **A** | The same, in Auto mode. |

Click the icon for the status and the three modes.

## Install

Requirements: macOS 12 or later, an administrator account, and [Homebrew](https://brew.sh). If you don't use Homebrew, install [SwiftBar](https://swiftbar.app) yourself first.

```bash
git clone https://github.com/slaven-ostojic/mac-keep-awake.git
cd mac-keep-awake
./install.sh
```

Or without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/slaven-ostojic/mac-keep-awake/main/install.sh | bash
```

The installer shows what it will do and asks before changing anything. It asks for your Mac password once, to add the sudo rule.

After installing:

1. **Turn on Launch at Login**: click the icon, then **SwiftBar > Preferences…**. Without it the icon is gone after a restart, but the sleep setting is saved in the system power settings and can still be on.
2. **Allow SwiftBar notifications** when macOS asks. The heat warning is shown there.

## Auto mode (Claude Code)

Start a task in Claude Code, close the lid and walk away. The Mac stays awake while Claude works, and goes to sleep as soon as Claude finishes or stops to ask you something, instead of draining the battery doing nothing.

Auto mode works through [Claude Code hooks](https://code.claude.com/docs/en/hooks). `install.sh` offers to add them to `~/.claude/settings.json` (it asks first and keeps a backup). They call the plugin like this:

| Claude Code event | Keep Awake |
|---|---|
| You send a prompt, or Claude uses a tool | Keep the Mac awake |
| Claude finishes its answer, or fails with an API error | Allow sleep, unless a background task is still running |
| Claude has been idle, waiting for your next prompt, for about a minute | Allow sleep |
| The session ends | Allow sleep |

- **Several sessions.** Each Claude session holds the Mac awake on its own. The Mac sleeps only after the last one lets go.
- **Crashed sessions.** A session that dies without saying it's done is dropped at the next refresh, within 10 seconds. A session that hasn't used a tool for 3 hours is also dropped.
- **Lid already closed.** When the last session lets go with the lid closed and the Mac on battery, the Mac is put to sleep right away (`pmset sleepnow`). When it's plugged in, sleep is only allowed again, so a closed MacBook driving an external display keeps running.
- **Off and On are manual.** The hooks do nothing unless Auto is selected, so if Auto misbehaves, pick Off or On and Keep Awake works as before.

Good to know:

- **A permission prompt counts as working.** While Claude waits for you to approve something, the Mac stays awake, so the command you approve can finish with the lid closed. If you walk away from a prompt, the Mac stays awake until you answer it, or for at most 3 hours.
- **Stopping Claude with Esc** doesn't send "done" to hooks. Sleep is allowed again about a minute later, when Claude Code reports that it's idle.

## What gets installed

| What | Where | Why |
|---|---|---|
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | `/Applications/SwiftBar.app` | Open-source app that turns a shell script into a menu bar item. Installed with Homebrew if you don't have it. |
| The plugin `keep-awake.10s.sh` | SwiftBar's plugin folder. If you haven't picked one: `~/.swiftbar` | Reads the sleep setting every 10 seconds and draws the icon and menu. |
| A sudo rule | `/etc/sudoers.d/keep-awake` | Lets your user run exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password, so the icon can switch. No other command and no other arguments. |
| Claude Code hooks, only if you say yes | `~/.claude/settings.json` | Tell Keep Awake when Claude starts and stops working, for Auto mode. Your other settings and hooks are kept. Needs `jq`, which comes with macOS 15 and later. |
| Auto mode state | `~/.keep-awake` | Whether Auto is selected, and one small file per Claude session that is working. |

The sudo rule is checked with `visudo` before it's installed. A broken file in `/etc/sudoers.d` would stop `sudo` from working at all.

## Uninstall

```bash
./uninstall.sh
```

This turns normal sleep back on, then removes the sudo rule, the plugin, the Claude Code hooks and `~/.keep-awake`. SwiftBar stays installed; remove it with `brew uninstall --cask swiftbar` if you don't use it for anything else.

Without a clone:

```bash
curl -fsSL https://raw.githubusercontent.com/slaven-ostojic/mac-keep-awake/main/uninstall.sh | bash
```

## Troubleshooting

- **No icon.** Open SwiftBar from Applications. Then check **System Settings > Menu Bar** and make sure SwiftBar is allowed there. On a MacBook with a notch, a crowded menu bar can hide icons behind the notch.
- **Clicking does nothing, or a notification says "could not switch".** The sudo rule is missing. Run `./install.sh` again.
- **Auto mode says "Claude Code hooks are missing".** Run `./install.sh` again and say yes to the hooks, then restart your Claude Code sessions.
- **Auto mode keeps the Mac awake, but Claude isn't doing anything.** Look at `~/.keep-awake/claude`: each file is a session holding the Mac awake. Picking Off clears them.
- **Check the setting from Terminal:** `pmset -g | grep SleepDisabled` shows `1` when Keep Awake is ON.

## Why not `caffeinate` or Amphetamine?

`caffeinate` and most keep-awake apps prevent idle sleep, but closing the lid still puts the Mac to sleep. `pmset disablesleep` also blocks lid-close sleep, which is what you want for downloads, builds or remote sessions with the lid shut. It's an undocumented `pmset` option (not in `man pmset`), so Apple could change it in a future macOS.

## License

[MIT](LICENSE)
