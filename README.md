# Keep Awake

A menu bar icon for macOS that stops your Mac from sleeping, **including with the lid closed**, and shows you at a glance whether that's on.

One click switches between:

```bash
sudo pmset -a disablesleep 1   # Keep Awake ON: the Mac never sleeps
sudo pmset -a disablesleep 0   # normal sleep
```

> [!WARNING]
> **Heat.** While Keep Awake is ON, a closed MacBook keeps running. In a bag, a sleeve or under a pillow it can get very hot and drain the battery to zero.
> Turn it off before you pack the Mac away. The icon turns red when Keep Awake is ON and the Mac is on battery, and a notification warns you each time you turn it on.

## What you see

| Icon | Meaning |
|---|---|
| Moon | Keep Awake is off. The Mac sleeps normally. |
| Orange cup | Keep Awake is ON and the Mac is plugged in. |
| Red cup | Keep Awake is ON and the Mac is on battery. |

Click the icon for the status and the switch.

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

## What gets installed

| What | Where | Why |
|---|---|---|
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | `/Applications/SwiftBar.app` | Open-source app that turns a shell script into a menu bar item. Installed with Homebrew if you don't have it. |
| The plugin `keep-awake.10s.sh` | SwiftBar's plugin folder. If you haven't picked one: `~/.swiftbar` | Reads the sleep setting every 10 seconds and draws the icon and menu. |
| A sudo rule | `/etc/sudoers.d/keep-awake` | Lets your user run exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password, so the icon can switch. No other command and no other arguments. |

The sudo rule is checked with `visudo` before it's installed. A broken file in `/etc/sudoers.d` would stop `sudo` from working at all.

## Uninstall

```bash
./uninstall.sh
```

This turns normal sleep back on, then removes the sudo rule and the plugin. SwiftBar stays installed; remove it with `brew uninstall --cask swiftbar` if you don't use it for anything else.

Without a clone:

```bash
curl -fsSL https://raw.githubusercontent.com/slaven-ostojic/mac-keep-awake/main/uninstall.sh | bash
```

## Troubleshooting

- **No icon.** Open SwiftBar from Applications. Then check **System Settings > Menu Bar** and make sure SwiftBar is allowed there. On a MacBook with a notch, a crowded menu bar can hide icons behind the notch.
- **Clicking does nothing, or a notification says "could not switch".** The sudo rule is missing. Run `./install.sh` again.
- **Check the setting from Terminal:** `pmset -g | grep SleepDisabled` shows `1` when Keep Awake is ON.

## Why not `caffeinate` or Amphetamine?

`caffeinate` and most keep-awake apps prevent idle sleep, but closing the lid still puts the Mac to sleep. `pmset disablesleep` also blocks lid-close sleep, which is what you want for downloads, builds or remote sessions with the lid shut. It's an undocumented `pmset` option (not in `man pmset`), so Apple could change it in a future macOS.

## License

[MIT](LICENSE)
