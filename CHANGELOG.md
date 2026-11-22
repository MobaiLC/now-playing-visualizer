# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.1] - 2026-11-22

After updating, restart the helper service (`systemctl --user restart nowplaying-viz`): the settings window needs the new helper (one design editor at a time). The protocol stays 3.

### Added
- **Settings window** for desktops without Plasma: `nowplaying-viz settings`, also opened by right-clicking the desktop card, and a "Now Playing Visualizer Settings" launcher entry (hidden in Plasma, which has Configure…). It has the same Design and Audio pages as the widget.

### Fixed
- The helper no longer crashes when `pactl` or `pw-dump` is not installed.

## [0.4.0] - 2026-11-21

After updating, restart the helper service (`systemctl --user restart nowplaying-viz`): the protocol went from 2 to 3, and the widget warns when the running service is older.

Upgrading a per-user install: `tools/install.sh` now refreshes the systemd units you already have even without `--systemd`, so the post-update check stops calling the removed `check.py`. Switching to the AUR package: remove the per-user install first, it is used before the package's copy.

### Added
- **Desktop card for Hyprland**, a quickshell component that shows the same card and bars as the Plasma widget, sharing its player and helper logic (`NowPlaying.qml`). Its size, corner, margins and monitor are the new `desktop.*` options (`desktop.monitor`, `anchor`, `marginX`, `marginY`, `width`, `height`), set in `config.json` and listed in [docs/CONFIG.md](docs/CONFIG.md).
- **`nowplaying-viz check`** validates `config.json` (JSON syntax, unknown options, wrong types, values out of range, a monitor that is not connected) and says what falls back to a default.
- **`nowplaying-viz doctor`** checks the whole setup: programs, QML modules, config, the helper service, players, and the audio chain up to CAVA hearing sound. Each line says what is wrong and what to do; `--json` for machines and `--notify` for a desktop notification.
- **`GET /status`** on the helper (protocol 3): `{protocol, service, clients, barClients, cava}` without starting CAVA, with the same same-user and Origin/Host checks as the websocket. `doctor` uses it.
- **`tools/install.sh` works without Plasma** (Hyprland and other desktops): it installs the helper, the `nowplaying-viz` command and the card, and tells you what is missing.
- **[AGENTS.md](AGENTS.md)**, a guide for AI assistants (install, change the look, fix problems), and a Claude Code skill built from it.
- **AUR packages** `now-playing-visualizer` and `now-playing-visualizer-git` in [`packaging/aur/`](packaging/aur/). Not published to the AUR yet; the release PKGBUILD still has `sha256sums=('SKIP')`, to be filled once the tag exists.
- Spanish translation of the new texts, including the `doctor` and `check` messages.

### Changed
- `nowplaying-viz doctor` replaces `check.py`, which is removed.
- The widget's player and helper logic moved out of `main.qml` into `NowPlaying.qml`, shared by the widget and the card. No change for the widget's behaviour.
- The README and the docs cover Hyprland and the AUR.

### Fixed
- The bars stayed flat with *Follow the player* or an app list: CAVA 1.0 opens a single mono input, and stereo streams were never linked into it. Every channel is now linked into a mono input, and PipeWire mixes them.
- A `config.json` that does not parse is never overwritten any more. Before, closing Design without Apply, Undo, a Design change or the Audio page wrote the defaults over it, losing the app list and saved presets; now the change is refused (Design says so) and the file is left as it is.
- A config section of the wrong type (for example a number where an object is expected) crashed `migrate` and with it the config check; it is now reported as one issue.

### Security
- `/status` follows the websocket's rules: connections from other users are refused, and requests with a foreign `Origin` or `Host` are rejected. It is read-only and starts nothing.

### Tested
- By hand on CachyOS with Plasma 6: the Plasma widget, confirmed visually, and the quickshell card, shown on KDE Wayland. The card has not been tried on a real Hyprland session yet.
- Automatically: unit tests, QML tests, MPRIS integration tests, the AUR `-git` package built and installed, the release package built, and namcap, all in Docker on a clean Arch (`tools/test-in-docker.sh`). The AUR packages were not installed from the AUR itself.

## [0.3.0] - 2026-11-01

### Fixed
- After an update, an older helper could keep running: the systemd service until it was restarted, or one the widget started, which outlived a Plasma restart. The helper now says which protocol it speaks; the widget replaces an outdated helper it started, and warns (with the command) when the outdated one is the service. `tools/install.sh` also restarts the service when it is running.
- The `NPV_PORT` variable only moved the helper: the widget kept connecting to 47811 and was left without a connection. The widget now reads it too (see [PROTOCOL.md](docs/PROTOCOL.md#port)).

### Security
- `NPV_PORT` must be a plain number from 1024 to 65535, checked the same way by the helper and the widget; anything else falls back to 47811 with a warning instead of crashing the helper. The widget waits to know the port before connecting, and the value never reaches a shell command.
- The widget no longer trusts what arrives on the port: malformed messages are dropped and bar values are clamped, so a program listening there instead of the helper can't break the widget with bad data.
- CI: actions are pinned by commit and the new container by digest, checkouts keep no token, and every job has a time limit.

### Added
- **Pick the player:** right-click the widget to show a given player instead of whichever is playing ("Automatic", the default). The choice is kept per widget; while that player is closed the widget goes back to automatic, and the menu still lists it so it can be unpinned. *Follow the player* and the D-Bus fallback follow the same pick.
- **Shuffle and repeat buttons**, on hover with the other controls, only for players that have them and allow control (Spotify, mpv with mpv-mpris…; not Firefox, Zen or Chromium, which don't). Repeat cycles off → playlist → track. On the cover they sit on a second, smaller row. Can be turned off (`controls.shuffleRepeat`).
- **Import and export presets** in **Design → Presets**: export the design as it looks to a `.json` file, import one as a new preset. An imported file is never trusted: only known options with valid values are kept (the count of the rest is shown), text is cut to 256 characters, the app list and follow-the-player are never imported, and only regular files up to 256 KB are read. Undo and Cancel bring the previous design back.
- **Card colours from the cover art** (`panel.colorSource`): background, border, texts and progress bar follow the song's cover and fade into the next one. The text is white or near-black, whichever contrasts more (WCAG ratio), and the accent is nudged until it stands out; with no cover the configured colours are used. Off by default.
- **Blurred cover art as the background** (`panel.coverBackground`, `coverBlur`, `coverDim`), with the card's own colour laid over it so the text stays readable. Off by default, and never drawn in the preset thumbnails.
- **Peak markers for every style:** a thin line over the wave, and marks around the ring in circular mode. They were limited to linear bars and blocks.
- **Equalizer** for the bars (`audio.eq.bass`, `mid`, `treble`) and the option to turn off CAVA's automatic sensitivity (`audio.autoSensitivity`). With the defaults, CAVA gets exactly the same config as before.
- QML tests (`tests/qml/`, run with `qmltestrunner`) for the port and message checks, the renderers' geometry and colours, the readable cover colours and the player choice, in CI on Arch.
- MPRIS integration tests (`tests/integration/run.sh`): fake players with and without shuffle/repeat, and mpv with mpv-mpris, on a private D-Bus session, checked through the helper and through Plasma's own MPRIS module. `tools/test-in-docker.sh` runs every test on a clean Arch. Both run in CI.

### Changed
- CAVA restarts only once its settings stop changing (0.4 s), so dragging a slider such as Sensitivity no longer blanks the bars on every step.
- In circular mode the "Horizontal" gradient (conical) now starts at the first bar, so it turns with **Rotation**; it used to stay at the top. At rotation 0 nothing changes. The gradient directions say what they do in circular mode.

### Tested
- Pick the player and shuffle/repeat: by hand with Spotify on Plasma 6.8, and automatically with fake MPRIS players (with and without shuffle/repeat) and mpv with mpv-mpris, through the helper and Plasma's MPRIS module, in CI and on a clean Arch in Docker. Liner, Riff, Haruna and Zen were not re-tested by hand for this release.
- Cover colours, blurred background, peaks and equalizer: by hand on Plasma 6.8 with Spotify.

## [0.2.0] - 2026-11-01

### Added
- **Follow the player:** an option under **Audio** that makes the bars listen only to the player shown in the widget, whichever it is, instead of a fixed list of apps (`audio.followPlayer`).

### Changed
- Lower CPU use:
  - The D-Bus media reader reads each player with one `GetAll` call instead of one process per property: about 5 processes a second instead of 23 with two players.
  - With **Follow the player**, the active player is looked up every 3 seconds instead of every second, so a player switch can take up to 3 seconds to reach the bars.
  - `schema.json`, the presets and the preset thumbnails are reused until they change, instead of being rebuilt on every slider step in **Design**.
  - Bar frames no longer wait on each widget: one that falls behind skips frames instead of holding up the others, and repeated frames (silence) are sent only once.
  - The bars stop redrawing once they stand still (paused music with **Hide when silent** off), except in the animated hue colour mode, and the palette and gradient are reused between frames.

### Fixed
- Stopping or restarting the helper service hung for about 10 seconds until systemd killed it, whenever a widget was connected. It now stops right away.

### Security
- The helper refuses connections from other users of the computer. `127.0.0.1` is shared by every local user, so before this anyone logged in could read the config, see what was playing and pause players or change their volume.
- Values that come from the players (bus names, track ids) can no longer be read by `busctl` as options.
- Saved presets are limited to 100; past the limit, **Design** asks you to delete one or save over an existing name.
- The CI workflow runs with a read-only token.

### Tested
- Follow the player, by hand: Riff, Spotify and Haruna. Song info and bars also checked on those three; their controls were not tested by hand.
- mpv has no MPRIS without the `mpv-mpris` plugin, so the widget can't show it or follow it; it can still drive the bars through the app list.

## [0.1.0] - 2026-10-31

First public version.

### Added
- **Now playing card:** cover art, title, artist, album/source, and progress interpolated between MPRIS updates.
- **Player controls:**
  - previous, play/pause and next on hover;
  - click or drag the progress bar to seek;
  - click the cover to raise the player;
  - mouse wheel for volume.

  Each control follows the player's MPRIS capabilities.
- **Visualizer:** CAVA in three styles (bars, blocks, wave), each with a circular mode.
  - Colour modes: gradient, one colour per bar, rainbow (optionally animated), cover-art colours, and the Plasma accent colour.
  - Optional falling peaks and glow; the bars fade out on silence.
- **Per-app audio:** selected apps are linked straight into CAVA through PipeWire, with no virtual device.
- **Layout:** horizontal, vertical or compact, chosen automatically from the widget's shape, and long titles that scroll.
- **Idle state:** the last song dimmed, a "Nothing playing" card, or hidden.
- **Design settings page,** generated from `schema.json`, with a live preview, tabs, preset cards, Undo, and Cancel that reverts. Ten built-in presets.
- **Audio settings page:** an OBS-style list of apps.
- **Helper:** standard library only, with a local WebSocket server that refuses connections from web pages, config validation and migrations, and a D-Bus fallback for MPRIS.
- **Optional systemd units:** a helper service, and a self-check after every pacman upgrade that notifies you when something broke.
- **English and Spanish.**
- **Documentation:** README, architecture, protocol, configuration reference (generated), decision records and contributing guide.
- **Quality checks:** helper unit tests and CI.

### Fixed (found in hands-on testing before release)
- After seeking, the progress bar stopped following the player, and other players then showed the song stuck at its end. The seek overwrote a QML binding; the position is now a plain value updated from the player.
- The mouse wheel did nothing on players without MPRIS volume, such as Liner. It now changes the app's PipeWire stream volume instead (no on-screen volume popup in that case).

### Known limitations
- Song info depends on a private Plasma module; the D-Bus fallback covers breakage.
- PipeWire is required.
- Player controls were tested by hand on Liner and on YouTube in Zen. Wheel volume on Liner (the PipeWire-stream path) was verified through the helper after the fix, but not re-tested by hand.
- Riff and Spotify have not been tested.
- Only tested on CachyOS with Plasma 6.8.
