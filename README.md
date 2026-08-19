# Omarchy Omaclip

A headless [Omarchy](https://omarchy.org/) shell plugin that, by default, opens [Omaclip](https://github.com/rhemvi/omaclip) in `special:scratchpad` and registers a copy hook that closes the workspace and pastes the copied entry into the focused window at the cursor location.

## Requirements

- Omarchy with shell plugin support
- [Omaclip installed and available as `omaclip`](https://github.com/rhemvi/omaclip#installation)
- `bash`, `grep`, `ip`, `pgrep`, `hyprctl`, and `wtype`

## Installation

```bash
yay -S omaclip-bin
omarchy plugin add https://github.com/rhemvi/omarchy-omaclip --enable
```

The plugin starts automatically after it is enabled. By default it waits for a usable network connection, launches Omaclip, and moves its window to `special:scratchpad` without opening that workspace.

Use Omarchy's native `Super+S` binding to toggle the default scratchpad. Selecting an Omaclip entry writes it to the clipboard, closes the scratchpad, and pastes the copied entry at the cursor location.

## Configuration

Plugin settings are stored inline in `~/.config/omarchy/shell.json`:

```json
{
  "plugins": [
    {
      "id": "omaclip.scratchpad",
      "clipboardMaxHistory": 100,
      "scratchpad": "scratchpad",
      "pasteOnCopy": true,
      "pasteDelayMs": 200
    }
  ]
}
```

All settings except `id` are optional.

| Setting | Default | Omaclip argument or behavior |
|---|---:|---|
| `executable` | `omaclip` | Executable name or absolute path |
| `clipboardMaxHistory` | `100` | `--clipboard-max-history` |
| `clipboardMaxNonPngImageMB` | Omaclip default | `--clipboard-max-non-png-image-mb` |
| `clipboardMaxPinned` | Omaclip default | `--clipboard-max-pinned` |
| `clipboardMaxPngImageMB` | Omaclip default | `--clipboard-max-png-image-mb` |
| `clipboardPollInterval` | Omaclip default | `--clipboard-poll-interval` |
| `configPath` | Omaclip default | `--config-path` |
| `debug` | Omaclip default | `--debug` |
| `peersList` | Omaclip default | Array joined with `;` for `--peers-list` |
| `mdnsInterface` | IPv4 default-route interface | `--peers-mdns-interface` |
| `peersPollInterval` | Omaclip default | `--peers-poll-interval` |
| `remoteClipboardsDisable` | Omaclip default | `--remote-clipboards-disable` |
| `remoteClipboardsMaxHistory` | Omaclip default | `--remote-clipboards-max-history` |
| `remoteClipboardsPollInterval` | Omaclip default | `--remote-clipboards-poll-interval` |
| `syncServerPort` | Omaclip default | `--sync-server-port` |
| `themeColorPath` | Omaclip default | `--theme-color-path` |
| `scratchpad` | `scratchpad` | Hyprland special workspace name |
| `pasteDelayMs` | `200` | Delay before invoking Omarchy's `Super+V` universal paste |
| `pasteOnCopy` | `true` | Paste the selected entry after closing the workspace |

The plugin owns `--copy-hook=omarchy-shell omaclip copied`; overriding it would disconnect the scratchpad copy flow.

Set `pasteOnCopy` to `false` to close the workspace after selecting an entry without pasting it. The selected entry remains available on the clipboard.

### Network interface selection

When `mdnsInterface` is omitted, the plugin discovers the interface carrying the IPv4 default route, waits for it to be up with a global IPv4 address, and passes it to Omaclip as `--peers-mdns-interface`.

Set `mdnsInterface` only to pin discovery to a particular interface:

```json
{
  "id": "omaclip.scratchpad",
  "mdnsInterface": "wlan0"
}
```

With an explicit interface, the plugin waits for that interface to be up with a global IPv4 address; it does not require the interface to carry the default route. When `remoteClipboardsDisable` is `true`, network readiness is not required.

### Dedicated Omaclip workspace

The default `scratchpad` workspace may contain other applications. To isolate Omaclip, configure another workspace:

```json
{
  "id": "omaclip.scratchpad",
  "scratchpad": "omaclip"
}
```

Then add a Hyprland binding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + K", "Omaclip", "omarchy-shell omaclip toggle")
```

The plugin's `toggle` method opens the configured workspace and focuses the exact Omaclip process.

## Status and troubleshooting

Inspect the service and its effective launch command:

```bash
omarchy-shell omaclip status | jq
```

Configuration changes affect the next Omaclip launch. The plugin adopts a compatible running process across Omarchy shell restarts so that Omaclip's in-memory history is not discarded.

To restart Omaclip and apply changed launch arguments:

```bash
kill "$(omarchy-shell omaclip status | jq -r '.processId')"
```

Restarting Omaclip clears its in-memory clipboard history and pins.

Validate a local checkout:

```bash
qmllint Service.qml
omarchy plugin validate .
```

## License

MIT
