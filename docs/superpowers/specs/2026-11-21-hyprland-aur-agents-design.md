# 0.4.0: Hyprland (quickshell), AUR and agent-friendly setup

Date: 2026-11-21 · Status: draft, pending approval

## Intent

Publish Now Playing Visualizer on the AUR so other people can install it, and make it
work on Hyprland as well as KDE Plasma. A first target user is a friend who runs
Hyprland and uses Claude: an AI agent must be able to **install it from zero, change
how it looks, and fix it when something fails** without a human reading the screen.

## Goals

1. **Hyprland desktop card.** The same card as the Plasma widget (cover, title,
   artist, progress, hover controls, bars) drawn by quickshell as a layer on top of
   the wallpaper and under windows. Clicks outside the card pass through.
2. **One drawing code base.** The Plasma widget and the quickshell card share the
   pure QtQuick parts, so a fix (like the mono-input fix in `[Unreleased]`) lands in
   both at once.
3. **Config by file on Hyprland.** `~/.config/nowplaying-viz/config.json` (preset +
   overrides, already hot-reloaded) is the only way to configure the quickshell card
   in this version. Position (corner + margins) and size are new options in it.
4. **`check` command.** Validates `config.json` and prints every problem: the option
   path, the bad value and the value that will be used instead. Exit code 0 when
   clean, non-zero otherwise. Human text by default, `--json` for agents.
5. **`doctor` command.** Runs the checks done by hand on 2026-11-21 and prints each
   with ✓/✗, the likely cause and the command that fixes it:
   - cava installed, and its version;
   - helper reachable on its port (and which protocol version answers);
   - systemd service state (when installed);
   - MPRIS players present, and which one is followed;
   - with per-app audio: the followed/selected streams are linked into cava's
     capture input;
   - cava is producing non-zero values while something plays (reads a short
     sample).
   Also `--json`.
6. **Agent guide.** A short Markdown guide (`AGENTS.md` in the package, installed to
   `/usr/share/doc/now-playing-visualizer/`) organised by the three tasks:
   install (Plasma and Hyprland paths kept separate, each step with how to verify
   it), change the look (pick nearest preset, then minimal `overrides`; a few
   recipes such as "match my theme colours", "smaller", "bottom corner"; run
   `check` after every edit; `docs/CONFIG.md` for everything else), and fix it
   (run `doctor`, follow its hints). The same file ships as a Claude skill
   (`SKILL.md` with frontmatter) under `/usr/share/now-playing-visualizer/skill/`;
   the README gives the one-line command to link it into `~/.claude/skills/`.
7. **AUR packages.** One package (no split): `now-playing-visualizer` pinned to the
   release tag, plus the existing `-git` package updated to match. Required deps are
   only what the helper and shared QML need; Plasma and quickshell become
   `optdepends`.

## Settled after the builder check

- **AUR names** (answered: nothing is on the AUR yet, per the README). Rename to
  `now-playing-visualizer` (release) and `now-playing-visualizer-git`; each
  `provides`/`conflicts` the other. Docs go to `/usr/share/doc/now-playing-visualizer/`.
  No `replaces` needed. README updated to the new names.
- **Existing `check.py` and pacman watcher** (Claude's call). Its system checks
  (commands, QML modules) move into `doctor` and `check.py` is removed; the pacman
  watcher unit runs `nowplaying-viz doctor --notify` instead. `doctor` detects the
  host (Plasma session or not, quickshell installed or not) and only requires the
  QML modules that host needs, so a Hyprland-only machine gets no false "broken"
  notification. `check` keeps meaning "validate config.json". README's
  "Check everything" section points to `doctor`.
- **`doctor` and cava samples** (Claude's call). `doctor` never subscribes to bars,
  so it never starts cava or creates links. When a card/widget is already
  connected it reads the live sample; otherwise that line says "not checked: no
  card or widget is running" with the hint to open one and run `doctor` again.

- **Monitors** (user's choice). One card, on the monitor named in `config.json`
  (a new option, e.g. `"monitor": "DP-1"`, the Hyprland/Wayland output name).
  Empty or unknown name = the primary monitor; an unknown name is also reported by
  `check`. Added to `schema.json` like the position/size options; the Plasma
  widget ignores it.

## Non-goals (this version)

- A standalone settings window. Planned for a later version (reuse of the Design
  page without Plasma deps).
- A bar module (Waybar or similar). Only the desktop card.
- Other compositors besides Hyprland. It may work anywhere quickshell's layer shell
  works, but only Hyprland is tested and documented.
- KDE Store publishing.

## Anti-goals

- The Plasma widget gets worse or loses features to make room for quickshell.
- The quickshell card interferes with the user's own quickshell config (bar,
  notifications). It must run as its own instance.
- The package writes to the user's home (`~/.claude`, `~/.config/hypr`). It only
  installs to system paths; the user or their agent links/enables things.
- `doctor` or `check` changing anything. They only read and report.

## Constraints

- Helper stays standard-library Python (ADR 002). New commands live in `helper.py`
  (subcommands), exposed as `/usr/bin/nowplaying-viz` wrapper.
- `schema.json` stays the single source of truth (ADR 006): new position/size
  options are added there, so `check`, the Plasma Design page and `CONFIG.md` pick
  them up. Bump `CONFIG_VERSION` + migration only if existing configs need it.
- The Plasma widget can start the helper itself; quickshell cannot, so on Hyprland
  the helper runs from the existing `nowplaying-viz.service`.
- Shared QML currently uses Plasma-only things: `i18n()` (2 calls in `Card.qml`) and
  Kirigami (`Icon`, `ImageColors`, `Theme`, `Units`). Kirigami is a plain library
  and becomes a required dependency; `i18n` needs a shim on the quickshell side.
- quickshell is in Arch `extra` (0.3.x at time of writing).

## Approaches

Considered:

- **A. Shared QML, split AUR package** (`-common`, `-plasma`, `-quickshell` from one
  PKGBUILD). Cleanest deps, but a split PKGBUILD is harder to write and review.
- **B. Shared QML, one AUR package, Plasma and quickshell as optdepends.** Chosen by
  the user. Much simpler to publish and maintain for a first AUR release; Plasma
  files are harmless on a system without Plasma. Cost: Kirigami likely required.
- **C. Separate quickshell copy of the QML.** Rejected: every fix done twice.

## Decided how (Claude's calls, accepted in conversation)

- quickshell card runs as its own config: `quickshell -p
  /usr/share/now-playing-visualizer/quickshell`, started from `exec-once` in
  `hyprland.conf`.
- Helper on Hyprland: the existing systemd user service.
- Position and size of the card set in `config.json`.
- `check`/`doctor` as subcommands of the helper.
- Release package pinned to the tag in addition to `-git`.

## Left to the builder

- Exact folder layout for the shared QML and how both hosts import it.
- How the quickshell side supplies what `main.qml` provides today (config,
  helper connection, MPRIS data: the helper's D-Bus path, since Plasma's private
  MPRIS module is unavailable).
- Names and ranges of the position/size options.
- `doctor` output wording and JSON shape.
- Tests: unit tests for `check`/`doctor` logic with mocked inputs (as in
  `tests/test_helper.py`), QML tests for anything moved into the shared folder, and
  the Docker/CI setup extended to build the AUR package.

## Release

Version 0.4.0. Includes the mono-input fix already in `[Unreleased]`. Usual steps:
`metadata.json`, CHANGELOG, PKGBUILDs, `release: 0.4.0` commit and tag. Nothing is
pushed to GitHub or the AUR without the user's confirmation.
