# Next Boot Selector

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin that lets you pick which EFI boot entry to load on the next reboot, straight from the bar or Control Center. Wraps `efibootmgr --bootnext` under the hood.

## Features

- **Bar pill** — single `restart_alt` icon, tints primary when a BootNext is pending
- **Control Center widget** — compound pill showing the pending target, with a scrollable picker detail
- **Scrollable entry list** — handles long EFI tables without hiding the action buttons
- **Filter** — hides PXE / CD-DVD / Removable / Network entries by default, regex is configurable
- **Reactive state** — picking an entry from the detail updates both the CC pill and bar pill instantly, shared across all plugin instances via `PluginService.setGlobalVar`
- **No polkit agent required** — shells out to `sudo -n` so it fails fast if the sudoers rule is missing, instead of hanging on an invisible password prompt

## Requirements

- DankMaterialShell (`dms-shell`) ≥ 0.1.0
- `efibootmgr` on `$PATH`
- `sudo` with a NOPASSWD rule for the two commands the plugin invokes (see below)
- A UEFI system — BIOS / CSM-only machines have nothing to select

## Installation

### 1. Clone into the plugins directory

```bash
git clone https://github.com/arcatva/dms-next-boot-selector.git \
  ~/.config/DankMaterialShell/plugins/NextBootSelector
```

### 2. Install the sudoers rule (required)

Writing EFI variables needs root. The plugin uses `sudo -n`, which requires a NOPASSWD rule scoped to exactly the two operations it performs:

```bash
sudo visudo -cf ~/.config/DankMaterialShell/plugins/NextBootSelector/dms-efibootmgr.sudoers
sudo install -m 0440 \
  ~/.config/DankMaterialShell/plugins/NextBootSelector/dms-efibootmgr.sudoers \
  /etc/sudoers.d/dms-efibootmgr
```

The rule grants `%wheel` passwordless access to:

```
/usr/bin/efibootmgr --bootnext [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]
/usr/bin/efibootmgr --delete-bootnext
```

Nothing else. Adjust the group name if your distro doesn't use `wheel`.

Smoke test:

```bash
sudo -n efibootmgr --bootnext 0001 && sudo -n efibootmgr --delete-bootnext
```

If both succeed without prompting for a password, you're good.

### 3. Enable in DankMaterialShell

1. Open DMS Settings (`Ctrl+,`)
2. Plugins tab → **Scan for Plugins** → toggle **Next Boot Selector** on
3. Add it to your bar layout (Appearance → DankBar Layout) or to Control Center (Appearance → Control Center Widgets)

## Configuration

All settings are editable via DMS Settings → Plugins → Next Boot Selector.

| Key | Default | Description |
|---|---|---|
| `privCmd` | `sudo -n` | Command prefix for `efibootmgr` writes. Swap for `pkexec` if you prefer a polkit prompt (and have an agent running). |
| `hideRegex` | `pxe\|cd/dvd\|removable device\|network device` | Case-insensitive JavaScript regex tested against each entry label. Leave empty to show every entry. |
| `rebootAfterSet` | `false` | When `true`, runs `systemctl reboot` immediately after setting BootNext. |

## How it works

- **Read path:** `efibootmgr` (no root needed for reads), parsed into `{id, active, label}` entries plus the current `BootCurrent` and `BootNext` values.
- **Write path:** `sh -c "<privCmd> efibootmgr --bootnext XXXX 2>&1"` so stderr ends up in stdout and surfaces in a toast on failure.
- **Cross-instance state:** DankMaterialShell creates a separate plugin instance for the Control Center *detail* panel, one without a `pluginId`, which means `pluginData` and `PluginGlobalVar` both break. State (`entries`, `bootCurrent`, `bootNext`) is shared via `PluginService.setGlobalVar` with a hardcoded plugin ID, and every instance subscribes to `onGlobalVarChanged` to stay reactive. Settings are read the same way via `SettingsData.getPluginSetting` instead of `pluginData`.
- **Layout:** Both the bar pill popout and the CC detail use the same pattern — header on top, buttons pinned to the bottom, a `DankFlickable` in between so long boot tables scroll without hiding the Clear / Reboot actions.

## Known limitations

- **First open after shell restart has a ~150 ms flash of the loading state.** The plugin reads `efibootmgr` asynchronously; the first instance to mount pays the cost, subsequent instances read from the shared global var. If you keep the bar pill enabled, the bar instance absorbs this cost at shell startup and the CC open is instant. If you only use the CC widget, the flash shows up on the first open per session.
- **External changes are not auto-detected.** If you run `efibootmgr` in a terminal while the shell is running, the widget won't notice until another write triggers a refresh. Click the bar pill or reopen the CC detail to force a re-read.
- **Uses `sudo -n` by default.** If the sudoers rule isn't installed, writes fail immediately with a toast rather than prompting — that's intentional. Switch `privCmd` to `pkexec` if you want a GUI prompt (requires a polkit agent like `hyprpolkit-agent` running in your session).

## License

MIT — see [LICENSE](./LICENSE).
