# Widget ↔ helper protocol

WebSocket on `ws://127.0.0.1:47811`. Text frames only.

## Port

The `NPV_PORT` environment variable changes the port, for the helper and for the widget. The widget reads it from plasmashell's environment, and a helper the widget starts inherits it, so set it where both see it, for example in `~/.config/environment.d/nowplaying-viz.conf` (`NPV_PORT=47899`), then log out and back in. The systemd service reads the same file.

Only a plain number from 1024 to 65535 is accepted; anything else (spaces, signs, other characters) is ignored with a warning, and both sides use 47811. The widget connects only once it knows the port, and the value never goes into a shell command.

The widget can't check who is listening on the port, so it treats every message as untrusted: invalid JSON or a message without a string `type` is dropped, and bar values are clamped to 0–1000, at most 256 per frame.

The helper refuses the handshake (HTTP 403) when it has an `Origin` header or a `Host` other than `127.0.0.1:<port>` / `localhost:<port>`, so web pages can't connect. Messages larger than 256 KB close the connection.

Every message is a JSON object with a `type`, except bar frames, which start with `B`.

## Helper → client

| Message | When | Payload |
|---|---|---|
| `schema` | right after connecting | `data`: `{version, tabs, groups, options: [ {key, …spec} ]}`. The options are a list because QML sorts object keys. |
| `config` | after connecting and whenever the config changes | `data`: full config, Qt colours (`#AARRGGBB`)<br>`web`: the same in web colours plus `presetName`, `presetList`, `userPresets`<br>`issues`: `[{code, detail}]` |
| `presets` | to subscribers of `presets`, on subscribe and on change | `data`: `[{name, user, config}]`, each preset merged over the defaults (web colours) |
| `editState` | after any design change from the editing page | `dirty`, `canUndo` |
| `apps` | reply to `listApps` | `data`: `[{id, name, icon}]` (icon is a theme icon name or empty) |
| `media` | once a second after `wantMedia` | `data`: `{track, artist, album, artUrl, length, position, rate, playing, identity, trackId, canControl, canPlayPause, canGoNext, canGoPrevious, canSeek, canRaise}` or `null` |
| `B…` | while CAVA runs, to subscribers of `bars` | `B` + semicolon-separated values 0–1000 |

Issue codes:
- `config_parse`, `preset_missing`, `invalid_option`, `out_of_range` — problems in the config;
- `cava_missing`, `cava_error` — problems running CAVA;
- `sink_error` — legacy, from versions that used a virtual sink.

## Client → helper

| Message | Fields | Effect |
|---|---|---|
| `subscribe` | `topics`: any of `config`, `schema`, `presets`, `bars`, `media` | Limits what this client receives. Without it a client gets everything. |
| `listApps` | | Replies with `apps`. |
| `setApps` | `apps`: list of app ids | Saves `audio.apps` (lower-cased, deduplicated, max 64). |
| `setFollowPlayer` | `value`: bool | Saves `audio.followPlayer`. |
| `beginEdit` | | Starts an edit session (snapshot + Undo history). |
| `setDesign` | `changes`: `{ "bars.count": 40, … }` | Writes valid, known options into `overrides`. |
| `setPreset` | `name` | Switches preset and drops bar overrides. |
| `resetDesign` | | Clears all overrides. |
| `savePreset` | `name` | Saves preset + overrides as a user preset and selects it. |
| `deletePreset` | `name` | Deletes a user preset. |
| `undo` | | Restores the previous design (editing page only). |
| `commitEdit` | | Keeps the current design (Apply/OK). |
| `wantMedia` | | Starts the D-Bus media reader (fallback mode). |
| `mediaAction` | `action`: `playPause`, `next`, `previous`, `raise`, `seek` (`value` in µs), `volume` (`value` ±delta, plus `identity`) | Controls the player in fallback mode. `volume` is always sent this way, with the player's MPRIS `identity`: the helper uses MPRIS `Volume` when it is writable, and the app's PipeWire streams (`wpctl`) otherwise. |
| `quit` | | Asks a widget-started helper to exit so the systemd service can take over. Ignored by `--service` helpers. |

## Compatibility

Adding a message type or field is backwards compatible, because both sides ignore what they don't know. Renaming or removing one is not: if you need to, add a `hello` message carrying a protocol version first.
