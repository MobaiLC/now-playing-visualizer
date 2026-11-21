# Now Playing Visualizer: guide for AI agents

Now Playing Visualizer shows the current song (cover, title, artist, progress) next to a real-time audio visualizer. It runs as a KDE Plasma 6 widget or, on Hyprland, as a quickshell desktop card. Both draw the same card and talk to one helper (`nowplaying-viz.service`), and both read one config file: `~/.config/nowplaying-viz/config.json`.

You cannot see the screen. Work from command output: `nowplaying-viz doctor` and `nowplaying-viz check` tell you what is wrong. Do not edit anything under `~/.config/hypr` or `~/.claude` yourself: show the user the line to add.

## Pick the path

- Plasma desktop: use **Install, Plasma**.
- Hyprland (or another layer-shell compositor, no Plasma): use **Install, Hyprland**.
- Not sure: `echo "$XDG_CURRENT_DESKTOP"`. `Hyprland` means the Hyprland path, `KDE` the Plasma one.

## Install

Run each verification command and read its output before the next step.

### Install, Hyprland (Arch)

1. Dependencies and package. From the AUR (once published; use `now-playing-visualizer-git` for the latest commit):
   ```bash
   yay -S now-playing-visualizer      # or paru -S, or makepkg -si in a clone of the AUR repo
   pacman -Q now-playing-visualizer   # prints the version
   ```
   AUR not available, or not Arch: install from git (the package list is `cava pipewire wireplumber python gettext quickshell`):
   ```bash
   git clone https://github.com/MobaiLC/now-playing-visualizer.git
   cd now-playing-visualizer
   tools/install.sh --systemd
   ```
   The script prints an `exec-once = quickshell -p ...` line. Keep it for step 3. Make sure `~/.local/bin` is in `PATH` (`command -v nowplaying-viz` must print a path).
2. Start the helper as a service:
   ```bash
   systemctl --user enable --now nowplaying-viz
   systemctl --user is-active nowplaying-viz    # must print: active
   ```
   (`tools/install.sh --systemd` already did this.)
3. Add the card to Hyprland. Ask the user to put one line in `~/.config/hypr/hyprland.conf`, or do it only if they ask you to:
   - AUR install: `exec-once = quickshell -p /usr/share/now-playing-visualizer/quickshell`
   - git install: `exec-once = quickshell -p ~/.local/share/plasma/plasmoids/com.github.mobailc.nowplayingvisualizer/contents/quickshell`

   Start it now without logging out: run that command after `exec-once = ` in the background, for example `quickshell -p <path> & disown`.
4. Verify:
   ```bash
   nowplaying-viz doctor      # exit 0 and no line starting with ✗
   ```
   On Hyprland the `links` and `audio` lines may say `skip` until a song plays: that is fine.
5. Optional: let the user link this guide as a Claude skill themselves: `ln -s /usr/share/now-playing-visualizer/skill ~/.claude/skills/now-playing-visualizer`.

### Install, Plasma

1. Package or git:
   ```bash
   yay -S now-playing-visualizer                 # once on the AUR
   pacman -Q now-playing-visualizer              # prints the version
   ```
   Or from git: `git clone https://github.com/MobaiLC/now-playing-visualizer.git && cd now-playing-visualizer && tools/install.sh --systemd`.
2. Helper service (optional, the widget starts the helper by itself without it):
   ```bash
   systemctl --user enable --now nowplaying-viz
   systemctl --user is-active nowplaying-viz    # must print: active
   ```
3. Restart Plasma so it loads the widget: `systemctl --user restart plasma-plasmashell`. Then the user right-clicks the desktop, **Add Widgets...**, **Now Playing Visualizer**.
4. Verify: `nowplaying-viz doctor`.

## Change the look

The config file is `~/.config/nowplaying-viz/config.json`:

```json
{ "version": 2, "preset": "lookas", "audio": { "apps": [] },
  "overrides": { "desktop": { "anchor": "topLeft" } }, "presets": {} }
```

- `preset` picks a built-in look. The presets are the files in `contents/code/presets/` next to `helper.py` (for example `lookas`).
- `overrides` holds only what differs from the preset. Put as little as possible there, nested like the option names: option `bars.glow.enabled` is `{"overrides": {"bars": {"glow": {"enabled": true}}}}`.
- Keep the rest of the file (`version`, `audio`, `presets`) as it is. Read the file before you edit it, and keep it valid JSON.
- The helper reloads the file within about a second; no restart.
- **Always run `nowplaying-viz check` after editing.** Exit 0 means valid. Fix every issue it prints (codes: `config_parse`, `preset_missing`, `invalid_option`, `out_of_range`, `unknown_option`, `unknown_monitor`) and run it again.
- The full list of options, types and ranges: `/usr/share/doc/now-playing-visualizer/CONFIG.md` (AUR) or `docs/CONFIG.md` in the git clone.

Recipes (each goes under `overrides`):

- **Match the user's theme colours.** Ask for, or read from their theme files, a background and an accent colour. Colours are `#RRGGBB` or `#RRGGBBAA`.
  ```json
  { "panel": { "color": "#1e1e2eE6" }, "bars": { "colorMode": "gradient", "colors": ["#89b4fa", "#cba6f7"] } }
  ```
  `bars.colors` is a list and is used when `bars.colorMode` is `gradient` or `perBar`. Other modes: `hue`, `cover`, `accent`.
- **Smaller or bigger card (Hyprland).** `desktop.width` (default 540, 200-3000) and `desktop.height` (default 162, 80-2000), in pixels:
  ```json
  { "desktop": { "width": 400, "height": 120 } }
  ```
- **Move the card (Hyprland).** `desktop.anchor` is `topLeft`, `topRight`, `bottomLeft` or `bottomRight` (default `bottomRight`); `desktop.marginX` and `desktop.marginY` are the distance from that corner in pixels (default 24):
  ```json
  { "desktop": { "anchor": "topLeft", "marginX": 32, "marginY": 32 } }
  ```
- **Another monitor (Hyprland).** `hyprctl monitors` lists the output names (`Monitor DP-1 ...`). Then `{ "desktop": { "monitor": "DP-1" } }`. Empty or missing means the first screen. A wrong name gives the `unknown_monitor` issue.
- **Which apps the bars listen to.** `audio.apps` is a list of app names (not under `overrides`); empty means the whole system.

The `desktop.*` options exist for the Hyprland card only; the Plasma widget is sized by the user in Plasma.

## Fix it

1. Run `nowplaying-viz doctor --json`. It prints `{"ok": ..., "host": ..., "checks": [...]}`. Each check has `id`, `status` (`ok`, `warn`, `fail`, `skip`), `message` and `hint`. Exit code 1 means at least one `fail`.
2. For every check that is not `ok`, do what its `hint` says (it is usually one command). Do not guess at fixes the hint does not give.
3. Run `nowplaying-viz doctor` again until no line starts with `✗`.

Check ids: `commands` (cava, pw-dump, pw-link, busctl, wpctl installed), `cava_version`, `qml_modules` (Plasma or quickshell QML modules), `config` (same as `check`), `service` (`nowplaying-viz.service`), `helper` (the helper answers on port 47811 and is current), `players` (a player is visible over MPRIS), `links` (per-app audio links), `audio`.

Common situations:

- **The card does not appear (Hyprland).** Is quickshell running: `pgrep -a quickshell`. If not, run the `exec-once` command by hand and read its output. Then `systemctl --user is-active nowplaying-viz` and `nowplaying-viz doctor`.
- **An outdated helper is running** (`helper` check): `systemctl --user restart nowplaying-viz`, then doctor again.
- **No bars, song shows.** `players` and `audio` in doctor; check `cava` is installed and, if `audio.apps` is set, that the app name matches a running app. An empty list captures the whole system.
- **No song.** The player must support MPRIS. `playerctl -l` lists players if `playerctl` is installed; `mpv` needs the `mpv-mpris` plugin.
- **A setting has no effect.** `nowplaying-viz check`; an `unknown_option` or `invalid_option` issue names the option and why.
- **Logs.** `journalctl --user -u nowplaying-viz -n 50` (service) or `~/.cache/nowplaying-viz.log` (helper started by the widget). Plasma widget errors: `journalctl --user -u plasma-plasmashell | grep nowplayingvisualizer`.
- **After a system upgrade.** Run `nowplaying-viz doctor` first: it reports a changed cava or missing QML module.

## Do not

- Do not edit files inside the installed package (`/usr/share/...`, or the plasmoid folder): they are overwritten on update. Settings live in `config.json`.
- Do not start a second helper by hand (port 47811 is shared); use the systemd service.
- Do not write outside `~/.config/nowplaying-viz/` unless the user asks.
