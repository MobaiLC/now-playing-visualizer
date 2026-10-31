# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - unreleased

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

### Known limitations
- Song info depends on a private Plasma module; the D-Bus fallback covers breakage.
- PipeWire is required.
- Click, drag and mouse-wheel controls have had little hands-on testing.
- Only tested on CachyOS with Plasma 6.8.
