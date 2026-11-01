# Architecture

This page is for people changing the code or maintaining a fork. For using the widget, see the [README](../README.md).

## The pieces

```
┌──────────────────────── plasmashell ────────────────────────┐
│ main.qml ── Card.qml ── Bars.qml ── renderers/*.js           │
│    │           ▲ action()                                    │
│    ├── MprisSource.qml ── org.kde.plasma.private.mpris        │
│    └── Helper.qml ──┐                                        │
│ configDesign.qml ───┤  (settings dialog, also uses Card.qml) │
│ configApps.qml ─────┤                                        │
└─────────────────────┼────────────────────────────────────────┘
                      │ WebSocket  ws://127.0.0.1:47811
┌─────────────────────┴──────── helper.py ─────────────────────┐
│ config: schema.json + presets/*.json + config.json → validate │
│ CAVA (pipewire input) ── links selected apps into it          │
│ MPRIS over D-Bus (busctl) — fallback only                     │
└───────────────────────────────────────────────────────────────┘
```

| File | Role |
|---|---|
| `ui/main.qml` | The plasmoid. Picks the media source, interpolates the song position, handles the idle state and forwards card actions to the player. |
| `ui/Card.qml` | The card itself (cover, texts, progress, controls, bars). A pure view: data in through properties, user actions out through `action(name, value)`. The widget, the live preview and the preset thumbnails all use it. |
| `ui/Bars.qml` | Smoothing, falling peaks, silence fade and glow. Drawing is delegated to `renderers/`. |
| `ui/renderers/` | Pure JavaScript: `common.js` (geometry), `palette.js` (colour modes), one file per style, `registry.js` (picks the renderer). |
| `ui/MprisSource.qml` | The **only** file that imports Plasma's private MPRIS module. Loaded through a `Loader`, so if a Plasma update breaks it, only this file fails. |
| `ui/Helper.qml` | WebSocket client for the helper; starts the helper through `Launcher.qml` when it isn't running. |
| `ui/Launcher.qml` | Starts `helper.py` with Plasma5Support; also behind a `Loader` for the same reason. |
| `ui/configDesign.qml` | The Design page, generated from `schema.json`. |
| `ui/configApps.qml` | The Audio page (OBS-style app list). |
| `code/helper.py` | The helper (see below). Standard library only. |
| `code/schema.json` | Every option: type, default, range, label, group, tab and visibility conditions. |
| `code/presets/*.json` | Built-in presets, each listing only what differs from the defaults. |
| `code/check.py` | Self-check of programs and QML modules, used after package upgrades. |

## Data flow

1. **Config.** The helper merges, in order:
   - the defaults from `schema.json`;
   - the chosen preset;
   - the user's `overrides`.

   It validates the result against the schema and sends it to every client. The settings pages get it in web colour format, so the user sees `#RRGGBBAA`; the widget gets it in Qt's `#AARRGGBB`. The helper polls `config.json` every 0.5 s, so a hand edit shows up immediately.
2. **Bars.** CAVA runs only while at least one client subscribes to `bars`. Each output line goes out as a text frame, `B` followed by the values (`B12;340;…`, each 0–1000). `Bars.qml` smooths them every frame with `attack` and `decay`.
3. **Song.** `MprisSource.qml` follows the playing (or preferred) player. If it can't load, or `advanced.forceDbusMedia` is set, the widget sends `wantMedia` and the helper polls MPRIS over D-Bus once a second.
4. **Controls.** `Card.action()` → `main.qml` → `MprisSource.act()`, or `mediaAction` to the helper in fallback mode. Controls are shown only when the player reports the matching `Can*` capability.
   - Volume always goes through the helper. Many players (Liner and other Chromium/Electron apps) have no MPRIS `Volume`, so the helper changes the app's own PipeWire streams instead. It finds them by matching the MPRIS bus owner's process id, or the app name.

## Per-app audio

When `audio.apps` is not empty, or `audio.followPlayer` is on:
- CAVA is started with `method=pipewire` and a target that doesn't exist, so it can be found among the PipeWire nodes and never captures anything by itself.
- Every second, while CAVA runs, the helper:
  - links the output ports of the selected apps' streams into CAVA's input ports. With `audio.followPlayer` the list is ignored and it links the active player's streams instead: the player is picked like the D-Bus fallback picks the one to show (playing and preferred first), and its streams are found by the MPRIS connection's PID or by app name, as for volume;
  - removes any other link into it, including WirePlumber's fallback link to the default microphone.

No virtual device is created. When the list is empty and `audio.followPlayer` is off, CAVA captures the default output (`source=auto`).

## Edit sessions (Apply / Cancel)

The Design page applies changes live, but the helper keeps a snapshot of the design while the page is open:
- `beginEdit` takes the snapshot.
- Each change pushes the previous design onto an Undo history; slider drags within 0.8 s count as one step.
- `commitEdit` (Apply/OK) replaces the snapshot with the current design.
- If the page disconnects without committing (Cancel, closing the dialog, a crash), the helper waits 1.5 s and restores the snapshot.

The commit is sent twice: directly from the page, and through Plasma's own config (`designCommit`, which `main.qml` forwards). That way OK still works if the dialog closes the page's socket first. See [adr/005](adr/005-live-edit-with-revert.md).

## Robustness

- **Isolated imports:** the private MPRIS module and Plasma5Support are each loaded through a `Loader`, with a fallback.
- **Helper:**
  - No third-party Python packages; the WebSocket server is about 100 lines of standard library.
  - It refuses handshakes that carry an `Origin` header or an unexpected `Host`. Browsers always send `Origin` and Qt's client never does.
  - It caps message size.
  - It only writes options that exist in the schema, with valid values.
  - It writes files atomically, with mode 0600.
- **Config:** `config.json` carries a `version`; `migrate()` upgrades older files one step at a time.
- **Self-check:** `check.py` runs after every `pacman` transaction (optional systemd path unit) and notifies the user when a dependency is missing.

## Processes and lifetime

- **Started by the widget:** `setsid python3 -I helper.py`. It exits 60 s after the last client disconnects.
- **Started by systemd:** `helper.py --service` stays up. If a widget-started helper already holds the port, the service asks it to `quit` and takes over.
- **Single instance:** only one helper runs at a time; the TCP port is the lock.
