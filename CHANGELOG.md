# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
