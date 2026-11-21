# Standalone settings window (Design + Audio) for Hyprland

Date: 2026-11-21 · Status: draft, pending approval · Follows 0.4.0

## Intent

0.4.0 made the card work on Hyprland (confirmed by the user on a real Hyprland), but
there the only way to configure it is editing `~/.config/nowplaying-viz/config.json`.
Plasma users get the visual Design page with live preview, presets and tabs. This
adds the same settings, as their own window, for any desktop without Plasma.

## Goals

1. **A settings window** with two tabs, **Design** and **Audio**, showing the same
   content as the Plasma widget's settings pages (live preview, presets, style,
   colors, motion, panel, advanced; app list and "follow the player").
2. **One code base for the pages.** The content of `configDesign.qml` and
   `configApps.qml` is moved out of Plasma's `KCM.SimpleKCM` frame into shared
   page components; the Plasma settings and the new window both use them. A change
   to a page lands in both.
3. **Own Apply / OK / Cancel** buttons in the window, with the same meaning as in
   Plasma: Apply keeps the live-edited design (`commitEdit`), OK = Apply + close,
   Cancel or closing the window without applying reverts it (the helper already
   reverts when the editing client disconnects without a commit). Closing with
   unapplied changes asks first, as Plasma does.
4. **Three ways to open it, all running the same command**:
   `nowplaying-viz settings`; an entry in the application launcher
   (`.desktop` file); right-click on the quickshell card.
5. **Runs with Qt's own QML runtime** (`qml` from `qt6-declarative`, already a
   required dependency), so it works whether or not the card is running and on
   any desktop, Plasma included.
6. English only outside Plasma. The Plasma settings keep their translations.

## Non-goals

- Translating the window outside Plasma (a later version could have the helper
  serve the gettext catalog).
- New options or a redesign of the pages.
- A settings UI inside the quickshell process (approach A, rejected).

## Anti-goals

- The Plasma settings dialog changes behaviour or loses its Spanish text.
- The window writes over a `config.json` that does not parse (0.4.0 fix: the
  helper replies `config_unreadable`; the window must show it like Design does
  today, not retry blindly).
- Two settings windows (or the window and Plasma's Design page) silently fighting
  over the same live edit.

## Constraints

- Shared page files may import only what exists outside Plasma: QtQuick,
  QtQuick.Controls, QtQuick.Layouts, QtQuick.Dialogs, QtCore, Kirigami. No
  `org.kde.kcmutils`, `org.kde.plasma.*`.
- `i18n()` is provided by Plasma only. On the Plasma side every user-visible
  string must still go through `i18n()`; outside Plasma the same strings must show
  in English without errors.
- The helper protocol (3) and its live-edit messages (`beginEdit`, `commitEdit`,
  `undo`, design edits, `editState`) are reused as they are; a protocol change
  only if strictly needed.
- `cli.py` keeps working under `python3 -I`; the wrapper `tools/nowplaying-viz` is
  the single entry point. Packages install only to system paths
  (`/usr/share/applications` for the `.desktop` file); `tools/install.sh` installs
  the per-user `.desktop` into `~/.local/share/applications`.
- Everything is installed through the existing single install script
  (`packaging/install.sh`) and `tools/install.sh`.

## Approaches

- **A. Window inside the quickshell card process.** No new process, but it exists
  only while the card runs, and the command/launcher would need quickshell IPC.
- **B. Own window run with Qt's `qml` runtime.** Chosen by the user. Works without
  the card, on any desktop, one way to open it; an agent or a person opens it the
  same way.
- **C. Rewrite settings as a web page or in Python.** Rejected: redoes ~700 lines
  and loses the live preview.

## Decided how (Claude's calls)

- The window is a new top-level QML file in the package (e.g.
  `contents/settings/settings.qml`), started by `nowplaying-viz settings`, which
  finds the `qml` runtime (`qml6`, `qml`, or `/usr/lib/qt6/bin/qml`) and reports a
  clear error if none is found.
- `doctor` gains no new check (the `qml` runtime is part of `qt6-declarative`,
  already checked through QML modules).
- One editor at a time (see "Settled after the builder check").
- The card's right-click opens the window (see below for how) through quickshell's
  process API; right-click is currently unused on the card.
- `AGENTS.md` and both READMEs mention the command for people; agents keep
  editing `config.json` + `check`.

## Settled after the builder check (Claude's calls)

- **Helper connection:** the window reuses `Helper.qml` as the card does: outside
  Plasma its `Launcher` fails to load, it uses the default port and never starts
  the helper. While the helper can't be reached the window shows a message with
  `systemctl --user start nowplaying-viz` (and `nowplaying-viz doctor`) instead
  of the pages; it connects as soon as the helper is up. `NPV_PORT` stays
  unsupported outside Plasma, as for the card.
- **Look outside KDE:** Kirigami is already a required dependency. `settings`
  sets `QT_QUICK_CONTROLS_STYLE` only when the user hasn't: `org.kde.desktop` if
  that style is installed, otherwise `Fusion`. The preview's media comes through
  `NowPlaying.qml`, whose MPRIS loader already falls back to the helper outside
  Plasma.
- **One editor at a time, everywhere:** the helper refuses a second `beginEdit`
  while another client owns the edit, replying with a new `editBusy` message
  (additive: older clients ignore it, no protocol bump). The shared Design page
  shows "Design is being edited in another window" and stays read-only; this
  covers window vs window, window vs Plasma, and two Plasma widgets. When the
  owner disconnects the edit is released as today, and the waiting page can take
  it (retry `beginEdit` on the helper's notice or a short timer). No lock file.
- **No lost changes on OK:** OK sends `commitEdit` and quits only after the
  helper confirms (its next `editState` with no pending revert, or a dedicated
  ack), with a short timeout that keeps the window open and shows an error rather
  than quitting silently. The close prompt uses the `editState` dirty flag.
- **Layout:** the shared pages live as components in `contents/ui` (e.g.
  `DesignPage.qml`, `AudioPage.qml`); `configDesign.qml` and `configApps.qml` stay
  as thin `KCM.SimpleKCM` wrappers, so Plasma's `config.qml` is unchanged. The
  window is `contents/settings/settings.qml` importing `../ui` (plain `qml` allows
  it).
- **Translations:** the Plasma side keeps calling the global `i18n`/`i18np`/
  `i18nc`, so `extract-messages.sh` and the Spanish catalog keep working.
  Outside Plasma the window provides English stand-ins with KDE's `%1…%n`
  substitution and plural choice.
- **Launcher entry:** `Name=Now Playing Visualizer Settings`,
  `Icon=view-media-visualization`, `NotShowIn=KDE;` (Plasma users have the
  widget's own settings). The package's file uses `Exec=nowplaying-viz settings`
  (`/usr/bin`); `tools/install.sh` writes the absolute `~/.local/bin` path.
- **`settings` subcommand:** implemented in `cli.py` (testable): finds the `qml`
  runtime with `shutil.which` (`qml6`, `qml`, then `/usr/lib/qt6/bin/qml`), sets
  the style, then `os.execvp`s it; exit 1 with a clear message if no runtime.
  Wrapper and usage text list `settings`.
- **Right-click on the card:** runs `python3 -I <package>/contents/code/cli.py
  settings` by absolute path (no `PATH` dependence under `exec-once`); repeated
  clicks are harmless because a second window shows the "edited in another
  window" state (it may close itself if the builder prefers, but must not take
  the edit).

## Left to the builder

- How shared pages get `i18n` on Plasma and plain English elsewhere (e.g. a
  translate function passed in as a property, or a tiny shim the window
  provides) — must keep Plasma's extraction (`tools/extract-messages.sh`) working.
- Exact file layout of the shared pages and the window.
- How the window detects unapplied changes and asks before closing.
- Tests: compile tests for every new/moved QML file (Plasma-only files skip when
  Plasma is missing, as today), a QML test for the Apply/OK/Cancel → message
  mapping, unit tests for `nowplaying-viz settings` (runtime lookup, error when
  missing, single instance), packaging paths added to the Docker check.
