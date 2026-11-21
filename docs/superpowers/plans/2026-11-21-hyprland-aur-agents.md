# 0.4.0 Hyprland card, AUR, agent-friendly setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 0.4.0: a quickshell desktop card for Hyprland that shares the plasmoid's drawing code, `nowplaying-viz check`/`doctor`, an agent guide, and AUR packages.

**Architecture:** The non-Plasma logic of `main.qml` moves into a shared `NowPlaying.qml`; the plasmoid and a new quickshell config (`package/contents/quickshell/shell.qml`, importing `../ui`) both host it, so the quickshell card ships inside the same package folder. The helper gains a read-only `GET /status` endpoint; a new `cli.py` (run by `/usr/bin/nowplaying-viz`) implements `check` and `doctor` on top of helper functions and replaces `check.py`.

**Tech Stack:** QML/Qt 6, Kirigami, quickshell 0.3 (`Quickshell`, `Quickshell.Wayland`), Python 3.10+ stdlib, PipeWire tools, Arch PKGBUILD.

**Spec:** `docs/superpowers/specs/2026-11-21-hyprland-aur-agents-design.md`

## Global Constraints

- Helper and CLI: standard-library Python only, 3.10+ (ADR 002).
- `schema.json` is the single source of truth for options (ADR 006); `docs/CONFIG.md` is regenerated with `tools/gen-config-doc.py`, never hand-edited.
- The Plasma widget must not lose features or change behaviour.
- The quickshell card runs as its own instance: `quickshell -p <package>/contents/quickshell`; it never touches the user's own quickshell config.
- Packages install only to system paths; nothing writes to `~/.claude` or `~/.config/hypr`.
- `check` and `doctor` only read and report. `doctor` never subscribes to bars (so never starts CAVA or creates links).
- Package names: `now-playing-visualizer` (release, pinned to tag `v0.4.0`) and `now-playing-visualizer-git`; each `provides`/`conflicts` the other. Docs in `/usr/share/doc/now-playing-visualizer/`.
- Plasma and quickshell are `optdepends`; Kirigami, `qt6-declarative`, `qt6-websockets`, `cava`, `pipewire`, `wireplumber`, `python`, `systemd` are `depends`.
- Version 0.4.0. Nothing is pushed to GitHub or the AUR without the user's confirmation.
- Every user-visible string in QML goes through `i18n()` on the Plasma side; CLI strings through gettext like `check.py` did; Spanish translation updated in `translate/es.po`.

## Review Focus

1. A typo'd option in `overrides` (`"bars": {"styel": "wave"}`): `check` must name it as unknown and exit 1, not report "OK" — Task 4, `test_unknown_option_is_reported`.
2. No `config.json` yet (fresh install): `check` must not create the file, says defaults are in use, exits 0 — Task 4, `test_check_does_not_create_config`.
3. Helper not running: `doctor` prints a ✗ line with `systemctl --user start nowplaying-viz`, no traceback, exit 1 — Task 6, `test_doctor_helper_down`.
4. `desktop.monitor` names an output that is unplugged (or unplugged later): the card moves to the first screen instead of disappearing — Task 3, `test_pick_screen_falls_back`.
5. Hyprland-only machine (no Plasma QML modules): `doctor --notify` sends no "something broke" notification — Task 6, `test_quickshell_host_ignores_plasma_modules`.

---

### Task 1: Shared `NowPlaying.qml` (plasmoid unchanged)

**Files:**
- Create: `package/contents/ui/NowPlaying.qml`
- Modify: `package/contents/ui/main.qml` (lines 15–208 move out), `package/contents/ui/Card.qml:321,451`
- Test: `tests/qml/tst_components.qml`

**Interfaces:**
- Produces: `NowPlaying` (Item) with properties `cfg`, `issues`, `shownIssues`, `barValues`, `ready`, `panelCfg`, `pinnedPlayer` (string, writable, default `""`), `openPlayers`, `player`, `shownMedia`, `hasTrack`, `isPlaying`, `idle`, `whenIdle`, `positionMs`, `lengthMs`, `useFallback`, and functions `mediaAction(name, value)`, `send(obj)` (forwards to its `Helper`). Signal-free; everything is bindable.
- Produces: `Card` gains `property string listeningText: "Listening to {title}"` and `property string nothingPlayingText: "Nothing playing"`, used instead of the two `i18n()` calls.

- [ ] **Step 1:** Add `"NowPlaying.qml"` to `test_compiles_data()` in `tests/qml/tst_components.qml`.
- [ ] **Step 2:** Run `/usr/lib/qt6/bin/qmltestrunner -input tests/qml`. Expected: FAIL on `NowPlaying.qml` (file missing).
- [ ] **Step 3:** Move the Helper, MPRIS loader + bindings, fallback, idle, position interpolation, timers and `mediaAction` from `main.qml` into `NowPlaying.qml` with no Plasma or Kirigami imports. `main.qml` keeps `PlasmoidItem`, the context-menu actions, `issueText()`, the warning icon and `fullRepresentation`, binds `nowPlaying.pinnedPlayer: Plasmoid.configuration.pinnedPlayer`, sends `commitEdit` via `nowPlaying.send`, and passes `listeningText: i18n("Listening to {title}")`, `nothingPlayingText: i18n("Nothing playing")` to `Card`.
- [ ] **Step 4:** Run `qmltestrunner -input tests/qml` and `python3 -m unittest discover -s tests`. Expected: all PASS.
- [ ] **Step 5:** Manual check on the user's Plasma: `tools/install.sh`, then **one** `systemctl --user restart plasma-plasmashell` (repeated quick restarts hit systemd's start limit; if it happens: `systemctl --user reset-failed plasma-plasmashell && systemctl --user start plasma-plasmashell`). Expected: card, bars, right-click player menu, controls, warning icon all as before.
- [ ] **Step 6:** Commit `Move the widget's player and helper logic into NowPlaying.qml`.

### Task 2: Desktop options in the schema

**Files:**
- Modify: `package/contents/code/schema.json` (new group + options), `docs/CONFIG.md` (regenerated)
- Test: `tests/test_helper.py` (`SchemaTests`, `PresetTests`)

**Interfaces:**
- Produces (all `"hidden": true`, group `desktop` in tab `panel`, label suffix "(Hyprland card)"):
  - `desktop.monitor` string, default `""` (output name, e.g. `DP-1`; empty = first screen)
  - `desktop.anchor` enum `topLeft|topRight|bottomLeft|bottomRight`, default `bottomRight`
  - `desktop.marginX`, `desktop.marginY` int 0–4000, default 24, unit px
  - `desktop.width` int 200–3000, default 540; `desktop.height` int 80–2000, default 162
- No `CONFIG_VERSION` bump (new options with defaults need no migration).

- [ ] **Step 1:** Write `test_desktop_options_have_defaults` (defaults built from schema contain `desktop.anchor == "bottomRight"`, `desktop.width == 540`) and `test_desktop_options_never_in_presets` (`"desktop.anchor" not in helper.design_options()`; `clean_design({"desktop": {"anchor": "topLeft"}})` returns `({}, 1)`).
- [ ] **Step 2:** Run `python3 -m unittest tests.test_helper -k desktop`. Expected: FAIL.
- [ ] **Step 3:** Add the group and options to `schema.json`; run `python3 tools/gen-config-doc.py` to regenerate `docs/CONFIG.md`.
- [ ] **Step 4:** Run the unit tests and `python3 tools/gen-config-doc.py --check`. Expected: PASS.
- [ ] **Step 5:** Commit `Add desktop.* options for the Hyprland card`.

### Task 3: quickshell card

**Files:**
- Create: `package/contents/quickshell/shell.qml`, `package/contents/ui/desktop.js`
- Test: `tests/qml/tst_desktop.qml`

**Interfaces:**
- Consumes: `NowPlaying` and `Card` (Task 1), `desktop.*` options in `cfg` (Task 2).
- Produces: `desktop.js` (`.pragma library`): `pickScreen(screens, name)` → the screen whose `.name === name`, else `screens[0]`, else `null`; `anchorsFor(anchor)` → `{top, bottom, left, right}` booleans (unknown → bottomRight).

- [ ] **Step 1: Spike (throwaway).** On this machine (KDE Wayland has layer-shell), write a minimal `shell.qml` that imports `"../ui"` and shows `Card` with fixed media, run `quickshell -p package/contents/quickshell`. Confirm: relative import outside the config dir works, Kirigami loads, `Kirigami.ImageColors` works. If the relative import is refused, fall back to symlinking `ui` into the quickshell folder at install time and note it in the plan.
- [ ] **Step 2:** Write `tst_desktop.qml`: `test_pick_screen_by_name` (`pickScreen([{name:"DP-1"},{name:"HDMI-A-1"}], "HDMI-A-1").name === "HDMI-A-1"`), `test_pick_screen_falls_back` (unknown name and `""` → `"DP-1"`; `[]` → `null`), `test_anchors` (`bottomRight` → `{bottom:true,right:true,top:false,left:false}`, `"nonsense"` → same).
- [ ] **Step 3:** Run `qmltestrunner -input tests/qml`. Expected: FAIL (no `desktop.js`).
- [ ] **Step 4:** Implement `desktop.js` and `shell.qml`: `ShellRoot` with one `NowPlaying`, one `PanelWindow` (`WlrLayershell.layer: WlrLayer.Bottom`, `WlrLayershell.namespace: "nowplaying-viz"`, `exclusiveZone: 0`, keyboard focus none, transparent colour), `screen: pickScreen(Quickshell.screens, cfg.desktop.monitor)` re-evaluated when `Quickshell.screens` changes, anchors/margins/size from `cfg.desktop`, `Card` filling it with the same opacity rule as `main.qml`. Add `shell.qml` and `desktop.js` to `tst_components` compile list (skips without quickshell).
- [ ] **Step 5:** Run qmltestrunner (PASS), then manual: `systemctl --user start nowplaying-viz && quickshell -p package/contents/quickshell`. Expected: card bottom-right of the first screen, bars move with music, hover controls work, clicks beside the card reach the desktop; editing `desktop.anchor` in `config.json` moves it live; the user's own quickshell bar is unaffected.
- [ ] **Step 6:** Commit `Add the quickshell desktop card for Hyprland`.

### Task 4: `check` command

**Files:**
- Create: `package/contents/code/cli.py`
- Modify: `package/contents/code/helper.py:270-311` (`load_config` split), `:214-223` (`validate` issue fields)
- Test: `tests/test_cli.py`

**Interfaces:**
- Produces in `helper.py`: `resolve_config(user: dict, schema: dict, builtin: dict) -> tuple[dict, list[dict]]` (pure: the effective config before `presetName`/QML colours, and its issues); `load_config()` keeps its behaviour on top of it. Issues from `validate` gain `"value"` (what was in the file) and `"used"` (what is used instead); the widget ignores extra keys.
- Produces in `cli.py`: `check(config_file: Path) -> tuple[int, dict]` and `main(argv: list[str]) -> int`. Report shape: `{"ok": bool, "config": str, "exists": bool, "issues": [{"code", "option", "value", "used"}]}`; codes `config_parse` (with `line`, `column`), `preset_missing`, `invalid_option`, `out_of_range`, `unknown_option` (any leaf of `overrides` or of a user preset that is not a schema option, found with `helper.leaves`), `unknown_monitor` (non-empty `desktop.monitor` not among the `name`s of `hyprctl monitors -j`; only checked when `hyprctl` is on PATH and answers). Exit 0 clean or no file, 1 issues, 2 unreadable JSON. `--json` prints the report; otherwise one line per issue: `✗ bars.style: "wavy" is not valid, using "bars"`.
- `cli.py` puts its own folder on `sys.path` (it runs under `python3 -I`) and imports `helper`.

- [ ] **Step 1:** Write `tests/test_cli.py` (same throwaway `XDG_CONFIG_HOME` pattern as `test_helper.py`): `test_clean_config_passes` (default config → code 0, `ok` true), `test_invalid_value_reports_value_and_used` (`overrides.bars.style = "wavy"` → issue `option "bars.style"`, `value "wavy"`, `used` = schema default, code 1), `test_unknown_option_is_reported` (`overrides.bars.styel` → `unknown_option`, code 1), `test_missing_preset` (code 1), `test_broken_json_gives_line` (code 2, `line` set), `test_check_does_not_create_config` (no file → code 0, `exists` false, file still absent afterwards), `test_unknown_monitor` (mocked `hyprctl monitors -j` → `[{"name":"DP-1"}]`, `desktop.monitor "HDMI-A-9"` → `unknown_monitor`, code 1; no `hyprctl` → no issue).
- [ ] **Step 2:** Run `python3 -m unittest tests.test_cli`. Expected: FAIL (no `cli.py`).
- [ ] **Step 3:** Split `resolve_config` out of `load_config`, add `value`/`used` to `validate`, implement `cli.check` and `cli.main` (subcommands `check`, `doctor` stub returning 2, `--json`).
- [ ] **Step 4:** Run all unit tests. Expected: PASS (existing `test_helper.py` unchanged and green).
- [ ] **Step 5:** Commit `Add nowplaying-viz check`.

### Task 5: Read-only `/status` in the helper

**Files:**
- Modify: `package/contents/code/helper.py` (`WsConn.handshake`, `cava_loop`/`send_bars` bookkeeping)
- Test: `tests/test_helper.py` (`WebSocketTests`)

**Interfaces:**
- Produces: `GET /status` (plain HTTP, same Host/Origin rule and same-user check as the websocket) answering `200` with JSON `{"protocol": int, "service": bool, "clients": int, "barClients": int, "cava": {"running": bool, "peak": int|null, "age": float|null}}`, then closing. `peak` = largest value in the last line CAVA wrote, `age` = seconds since it. Any other non-websocket request: unchanged (rejected).
- Produces: `status_snapshot() -> dict` (the JSON above), used by the handler.

- [ ] **Step 1:** Write `test_status_endpoint` (start the server as the existing websocket tests do; `GET /status` with `Host: 127.0.0.1:<port>` → 200, JSON has `protocol == helper.PROTOCOL`, `clients == 0`, `cava.running` false), `test_status_rejects_origin` (`Origin` header → 403), `test_status_does_not_start_cava` (after the request, `bar_clients()` is empty and `cava_proc` is still `None`).
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement: in `handshake`, a `GET /status` request line with no websocket key writes the response and raises `WsClosed`; track `state["bars_peak"]`/`state["bars_at"]` where CAVA lines are read (before the unchanged-frame skip).
- [ ] **Step 4:** Run all unit tests. Expected: PASS.
- [ ] **Step 5:** Commit `Helper: read-only /status for doctor`.

### Task 6: `doctor` command (replaces `check.py`)

**Files:**
- Modify: `package/contents/code/cli.py`, `packaging/systemd/nowplaying-viz-check.service:8`, `.github/workflows/ci.yml:37-38`
- Delete: `package/contents/code/check.py`
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: `/status` (Task 5), `helper.pw_dump`, `helper.active_player`, `helper.link_filter`/`player_stream`, `helper.CAPTURE_TARGET`, `check()` (Task 4).
- Produces: `detect_host() -> str` (`"plasma"` when `XDG_CURRENT_DESKTOP` contains `KDE` or `plasmashell` runs; else `"quickshell"` when `quickshell` is on PATH; else `"none"`), `doctor(notify: bool) -> tuple[int, dict]`. Report: `{"ok": bool, "host": str, "checks": [{"id", "status": "ok|warn|fail|skip", "message", "hint"}]}`. Check ids, in order: `commands` (cava, pw-dump, pw-link, busctl, wpctl — the `check.py` list), `cava_version`, `qml_modules` (the `check.py` modules; Plasma-only ones required only on host `plasma`; `Quickshell` and `Quickshell.Wayland` required only on host `quickshell`; module probing reuses `check.py`'s `qml` trick), `config` (summary of `check()`), `service` (`systemctl --user is-active nowplaying-viz`; on host `quickshell` inactive is `fail` with hint `systemctl --user enable --now nowplaying-viz`, on `plasma` it is `warn`), `helper` (`/status` reachable, protocol matches `helper.PROTOCOL`; down → `fail`, hint `systemctl --user start nowplaying-viz`), `players` (MPRIS players and the followed one), `links` (per-app mode only: streams of the followed/selected apps linked into the capture node; none → `fail` with the channel layouts found), `audio` (`skip` "no card or widget is running" when `barClients == 0`; `ok` when `peak > 0` and `age < 2`; `fail` "CAVA hears silence" when playing and peak is 0). Exit 1 if any `fail`. `--notify` sends one `notify-send` only when something is `fail` (critical) or `warn` (normal), like `check.py`. Text output: `✓`/`!`/`✗`/`-` + message, hint on the next line after `→`.

- [ ] **Step 1:** Write tests with `mock.patch` on `subprocess.run`/`shutil.which`/the status fetch/`pw_dump`: `test_doctor_helper_down` (connection refused → `helper` fail with the start hint, exit 1, no exception), `test_quickshell_host_ignores_plasma_modules` (host `quickshell`, Plasma modules missing → no `fail`, `--notify` not called), `test_plasma_host_requires_plasmoid_module` (missing `org.kde.plasma.plasmoid` → `fail`), `test_audio_skipped_without_card` (`barClients 0` → `skip`), `test_silent_cava_fails` (player playing, `peak 0` → `fail`), `test_unlinked_stereo_stream_fails` (fake `pw_dump`: stereo stream of the followed player, no links → `links` fail), `test_doctor_json_shape`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement `detect_host`/`doctor`; move `check.py`'s commands/modules tables and QML probe into `cli.py`; delete `check.py`; the check unit runs `cli.py doctor --notify`; CI compiles `cli.py` instead of `check.py`.
- [ ] **Step 4:** Run all unit tests. Expected: PASS. Manual: `python3 -I package/contents/code/cli.py doctor` here with music playing and the widget open → all ✓; with `audio.followPlayer` on and the fix from `64d1705` reverted locally, `links` is ✗ (then restore).
- [ ] **Step 5:** Commit `Add nowplaying-viz doctor, replacing check.py`.

### Task 7: `nowplaying-viz` command and install script

**Files:**
- Create: `tools/nowplaying-viz` (bash wrapper)
- Modify: `tools/install.sh`, `.github/workflows/ci.yml` (shellcheck list)

**Interfaces:**
- Produces: `nowplaying-viz <check|doctor> [--json] [--notify]` → `exec python3 -I <package>/contents/code/cli.py "$@"`, where `<package>` is the first that exists of `~/.local/share/plasma/plasmoids/com.github.mobailc.nowplayingvisualizer` and `/usr/share/plasma/plasmoids/com.github.mobailc.nowplayingvisualizer`. No arguments or `--help` prints usage, exit 0.
- `install.sh`: without `kpackagetool6` (Hyprland), copies `package/` to `~/.local/share/plasma/plasmoids/com.github.mobailc.nowplayingvisualizer` (same path, so the systemd units work unchanged); always installs the wrapper to `~/.local/bin/nowplaying-viz`; final message per host (Plasma: restart Plasma; otherwise: the `exec-once = quickshell -p …` line and `nowplaying-viz doctor`).

- [ ] **Step 1:** In a clean Arch container (`tools/test-in-docker.sh` image) without Plasma: `tools/install.sh --systemd` → exits 0, files under `~/.local/share/plasma/plasmoids/...`, `~/.local/bin/nowplaying-viz check` runs (exit 0). (Expected to fail before the change: `kpackagetool6: command not found`.)
- [ ] **Step 2:** Implement; `shellcheck tools/*.sh tools/nowplaying-viz` clean.
- [ ] **Step 3:** Re-run Step 1 (PASS) and `tools/install.sh` on this Plasma machine (still uses kpackagetool6).
- [ ] **Step 4:** Commit `Install without Plasma and add the nowplaying-viz command`.

### Task 8: Agent guide, skill and READMEs

**Files:**
- Create: `AGENTS.md`, `packaging/skill-frontmatter.md`
- Modify: `README.md`, `README.es.md`, `docs/ARCHITECTURE.md` (shared NowPlaying, quickshell host, cli.py), `CONTRIBUTING.md` (where `check`/`doctor` live)

**Interfaces:**
- Produces: `AGENTS.md` (English) with sections **Install** (Plasma and Hyprland paths separately; each step followed by its verification command: `pacman -Q`, `systemctl --user is-active nowplaying-viz`, `nowplaying-viz doctor`), **Change the look** (file location; preset then minimal `overrides`; recipes: match theme colours via `panel.color`/`bars.colors`, smaller card via `desktop.width`/`height`, move via `desktop.anchor`/margins/monitor with `hyprctl monitors` for names; always `nowplaying-viz check` after editing; full list in `/usr/share/doc/now-playing-visualizer/CONFIG.md`), **Fix it** (`nowplaying-viz doctor --json`, act on each `hint`, re-run). Under 200 lines.
- Skill = `packaging/skill-frontmatter.md` (`name: now-playing-visualizer`, one-line `description` covering install/look/fix) + `AGENTS.md`, concatenated at package time to `SKILL.md`.
- READMEs: Hyprland install section, `exec-once` line, `check`/`doctor`, how to link the skill: `ln -s /usr/share/now-playing-visualizer/skill ~/.claude/skills/now-playing-visualizer`, AUR names updated, "Check everything" points to `nowplaying-viz doctor`, status line no longer says the AUR is unpublished only after it is.

- [ ] **Step 1:** Write the docs. Verification: a fresh subagent given only `AGENTS.md` and a throwaway `XDG_CONFIG_HOME` is asked "make the card smaller and put it top-left" and must produce a `config.json` for which `cli.py check` exits 0 and `desktop.anchor == "topLeft"`.
- [ ] **Step 2:** Commit `Agent guide and Hyprland docs`.

### Task 9: AUR packages

**Files:**
- Create: `packaging/aur/now-playing-visualizer/PKGBUILD`, `packaging/aur/now-playing-visualizer-git/PKGBUILD` (moved from `packaging/aur/PKGBUILD`), `.SRCINFO` for both
- Modify: `tools/test-in-docker.sh` (build both packages with `makepkg` as the tester user and install them)

**Interfaces:**
- Both PKGBUILDs share `package()`: plasmoid to `/usr/share/plasma/plasmoids/$_id`; `/usr/share/now-playing-visualizer` → symlink to that plasmoid's `contents` (so `quickshell -p /usr/share/now-playing-visualizer/quickshell` works, as in the spec); systemd units with paths rewritten (existing sed); `tools/nowplaying-viz` to `/usr/bin/nowplaying-viz` with the per-user path check kept; `README.md`, `AGENTS.md`, `docs/CONFIG.md` to `/usr/share/doc/now-playing-visualizer/`; `SKILL.md` built to `/usr/share/now-playing-visualizer/skill/SKILL.md` (lives inside the plasmoid's contents via the symlink: put it at `contents/skill/`).
- `depends`/`optdepends` per Global Constraints; `optdepends=('plasma-workspace: Plasma widget' 'plasma5support: start the helper from the widget' 'kcmutils: settings pages' 'quickshell: Hyprland desktop card' 'libnotify: notifications from doctor --notify')`.
- Release: `pkgver=0.4.0`, `source=("$url/archive/refs/tags/v$pkgver.tar.gz")`, real `sha256sums` (filled at release, Task 10), `provides/conflicts=('now-playing-visualizer-git')`. Git: `provides/conflicts=('now-playing-visualizer')`.

- [ ] **Step 1:** Extend `tools/test-in-docker.sh`: build the `-git` package from the local checkout, install it with pacman, run `nowplaying-viz check` and `namcap` on the package. Expected before the change: FAIL (no such package dir).
- [ ] **Step 2:** Write both PKGBUILDs and `.SRCINFO` (`makepkg --printsrcinfo`).
- [ ] **Step 3:** Run `tools/test-in-docker.sh`. Expected: all tests pass, package installs, `/usr/share/now-playing-visualizer/quickshell/shell.qml` exists, `namcap` reports no errors.
- [ ] **Step 4:** Commit `AUR: now-playing-visualizer and now-playing-visualizer-git`.

### Task 10: Release 0.4.0 (local only)

**Files:**
- Modify: `package/metadata.json` (`Version`), `CHANGELOG.md`, both READMEs (version line), `translate/*.pot|es.po`, both PKGBUILDs

- [ ] **Step 1:** `tools/extract-messages.sh`; translate the new strings in `translate/es.po`; `tools/build-translations.sh` and `msgfmt --check` clean.
- [ ] **Step 2:** CHANGELOG `[0.4.0] - <date>`: Added (Hyprland card, desktop options, check, doctor, agent guide/skill, AUR packages), Changed (`check.py` → `doctor`), Fixed (mono input, already listed); what was tested by hand vs automatically, as in 0.3.0.
- [ ] **Step 3:** Full verification: unit tests, `qmltestrunner`, `gen-config-doc.py --check`, `tools/test-in-docker.sh`, and on this machine: Plasma widget + quickshell card + `nowplaying-viz doctor` all ✓.
- [ ] **Step 4:** Commit `release: 0.4.0` and tag `v0.4.0` locally. Ask the user before pushing; after the tag is on GitHub, fill the release PKGBUILD's `sha256sums` and regenerate `.SRCINFO`. Publishing to the AUR (needs the user's AUR account and SSH key) is a separate, confirmed step.
