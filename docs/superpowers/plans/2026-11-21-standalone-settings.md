# Standalone settings window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A settings window (Design + Audio tabs, own Apply/OK/Cancel) that runs with Qt's `qml` runtime on any desktop, sharing its pages with the Plasma settings.

**Architecture:** The content of `configDesign.qml`/`configApps.qml` moves into shared `DesignPage.qml`/`AudioPage.qml` (no kcmutils, no Plasma imports); the Plasma files become thin `KCM.SimpleKCM` wrappers. A new `contents/settings/settings.qml` hosts both pages in a window, started by `nowplaying-viz settings` (in `cli.py`), from a `.desktop` entry and from the card's right-click. The helper allows one design editor at a time and tells the others with `editBusy`.

**Tech Stack:** QML/Qt 6, Kirigami, QtQuick.Controls, quickshell 0.3 (`Quickshell.Io`), Python 3.10+ stdlib, Arch packaging.

**Spec:** `docs/superpowers/specs/2026-11-21-standalone-settings-design.md`

## Global Constraints

- Shared page files import only QtQuick, QtQuick.Controls, QtQuick.Layouts, QtQuick.Dialogs, QtCore, Kirigami — no `org.kde.kcmutils`, no `org.kde.plasma.*`.
- On Plasma every user-visible string still goes through `i18n`/`i18np`/`i18nc`; `tools/extract-messages.sh` and the Spanish catalog keep working. Outside Plasma: English, KDE-style `%1…%n` substitution and plural choice.
- Helper protocol stays 3; `editBusy` is an additive message (older clients ignore it).
- The window never writes over a `config.json` that does not parse (shows `config_unreadable` like Design does).
- Helper: standard-library Python only; `cli.py` runs under `python3 -I`; `tools/nowplaying-viz` stays the single entry point.
- Packages install only to system paths (`/usr/share/applications`); `tools/install.sh` writes the per-user `.desktop` to `~/.local/share/applications` with the absolute `~/.local/bin/nowplaying-viz` path; everything goes through `packaging/install.sh` / `tools/install.sh`.
- `.desktop`: `Name=Now Playing Visualizer Settings`, `Icon=view-media-visualization`, `NotShowIn=KDE;`, `Exec=nowplaying-viz settings` (package).
- Style: `settings` sets `QT_QUICK_CONTROLS_STYLE` only if unset — `org.kde.desktop` when installed, else `Fusion`.
- Manual checks never stop/restart the user's `nowplaying-viz` service or plasmashell, and never write the user's `~/.config/nowplaying-viz/config.json`; use a scratch `XDG_CONFIG_HOME` + a helper on a scratch port (`NPV_PORT`) for live checks.

## Review Focus

1. A second window (or Plasma's Design page) opened while one edits: the first keeps the edit; the second shows "Design is being edited in another window", is read-only and takes over when the first closes — Task 1 `test_second_editor_is_refused`, `test_edit_freed_on_disconnect`; Task 2 manual check.
2. A non-owner sends design messages anyway (stale page, old widget): nothing is written — Task 1 `test_non_owner_design_messages_are_refused`.
3. OK pressed while the helper is unreachable or never confirms: the window stays open and shows an error — Task 3 `test_ok_times_out_without_ack`.
4. No `qml` runtime installed: `nowplaying-viz settings` exits 1 with a clear message, no traceback — Task 4 `test_settings_without_runtime`.
5. Window closed by the compositor (Hyprland `killactive`) with unapplied changes: the design is reverted (helper's disconnect path) — Task 1 `test_owner_disconnect_reverts` (existing behaviour pinned).

---

### Task 1: One design editor at a time (helper)

**Files:**
- Modify: `package/contents/code/helper.py` (`begin_edit`, `on_message` design branch around `DESIGN_MESSAGES`)
- Test: `tests/test_helper.py` (`DesignEditTests`)
- Modify: `docs/PROTOCOL.md` (one entry for `editBusy`)

**Interfaces:**
- Produces: `beginEdit` from a client while `edit["owner"]` is another live client → reply `{"type": "editBusy"}` and no state change. Any of `DESIGN_MESSAGES` except `beginEdit`/`commitEdit` from a non-owner while an owner exists → reply `{"type": "editBusy"}`, nothing written. `commitEdit` unchanged (Plasma's Apply path sends it from the widget client). When the owner disconnects, `edit["owner"]` is cleared after the existing revert logic, so the next `beginEdit` succeeds.

- [ ] **Step 1:** Tests: `test_second_editor_is_refused` (ws A beginEdit → editState; ws B beginEdit → `editBusy`, owner still A), `test_non_owner_design_messages_are_refused` (A owns; B sends `setDesign` → `editBusy`, config file bytes unchanged), `test_edit_freed_on_disconnect` (A owns, A disconnects; B beginEdit → editState, owner B), `test_owner_disconnect_reverts` (A edits, disconnects without commit → design back to snapshot after `REVERT_GRACE`; pins existing behaviour).
- [ ] **Step 2:** `python3 -m unittest tests.test_helper -k edit` → the new refusal tests FAIL.
- [ ] **Step 3:** Implement in `helper.py`; document `editBusy` in `docs/PROTOCOL.md`.
- [ ] **Step 4:** `python3 -m unittest discover -s tests` → all OK.
- [ ] **Step 5:** Commit `Helper: one design editor at a time (editBusy)`.

### Task 2: Shared pages, thin Plasma wrappers

**Files:**
- Create: `package/contents/ui/DesignPage.qml`, `package/contents/ui/AudioPage.qml`, `package/contents/ui/tr.js`
- Modify: `package/contents/ui/configDesign.qml`, `package/contents/ui/configApps.qml` (become wrappers), `tools/extract-messages.sh` (only if the translate call changes), `tests/qml/tst_components.qml`, `tests/qml/tst_tr.qml` (new)

**Interfaces:**
- Consumes: `editBusy` (Task 1).
- Produces: `DesignPage` (Item) — properties `unsavedChanges: bool`, `canUndo: bool`, `busy: bool` (true after `editBusy`), `saveError: string`; functions `apply()` (flush + send `commitEdit`), `undo()`; signal `committed()` emitted when the helper's `editState` after an apply arrives with `dirty: false`. `AudioPage` (Item) — same content as today's Audio page. `tr.js` (NOT `.pragma library`, so it sees the importing file's context): `tr(msgid, ...args)`, `trp(singular, plural, n, ...args)`, `trc(context, msgid, ...args)` — call Plasma's `i18n`/`i18np`/`i18nc` when `typeof i18n === "function"`, else return English with `%1…%n` substituted and the plural picked by `n`. `configDesign.qml`: `KCM.SimpleKCM` with `DesignPage` inside, keeping `cfg_designCommit`, `unsavedChanges`, `saveConfig()` (calls `page.apply()` and sets `cfg_designCommit` as today). `configApps.qml`: `KCM.SimpleKCM` with `AudioPage`.
- Busy state: `DesignPage` shows an inline message `tr("Design is being edited in another window")`, disables every control, and retries `beginEdit` every 2 s until it gets `editState`.

- [ ] **Step 1:** Tests: `tst_tr.qml` — `test_substitution` (`tr("%1 of %2", "a", "b") === "a of b"`), `test_plural` (`trp("%1 preset", "%1 presets", 1) === "1 preset"`, `… 3) === "3 presets"`), `test_context` (`trc("ctx", "Open") === "Open"`); add `DesignPage.qml`, `AudioPage.qml` to `tst_components` compile list (they must compile without Plasma modules; kcmutils wrappers still skip when missing).
- [ ] **Step 2:** `qmltestrunner -input tests/qml` → FAIL (files missing).
- [ ] **Step 3:** Move the content; replace `i18n(`/`i18np(` in the shared pages with `Tr.tr(`/`Tr.trp(`; add `-kTr.tr:1 -kTr.trp:1,2 -kTr.trc:1c,2` (or equivalent) to `extract-messages.sh` so the same msgids are extracted.
- [ ] **Step 4:** Verify: `qmltestrunner` all pass; `tools/extract-messages.sh` then `git diff --stat translate/template.pot` shows only the new busy msgid added (no msgid lost); `python3 -m unittest discover -s tests` OK.
- [ ] **Step 5:** Manual (scratch helper on a scratch port + scratch `XDG_CONFIG_HOME`, with `qml` loading a tiny test harness that hosts `DesignPage`): page loads, preview draws, a second harness shows the busy message. Report what was seen in logs; Plasma visual check is left to the user.
- [ ] **Step 6:** Commit `Share the Design and Audio pages outside Plasma`.

### Task 3: The settings window

**Files:**
- Create: `package/contents/settings/settings.qml`, `package/contents/settings/flow.js`
- Test: `tests/qml/tst_settings_flow.qml`; add `settings/settings.qml` to the compile list (path from tests: `../../package/contents/settings/settings.qml`)

**Interfaces:**
- Consumes: `DesignPage`, `AudioPage` (Task 2), `Helper.qml` (connected state).
- Produces: `flow.js` (`.pragma library`): `next(state, event) -> {state, actions}` with states `idle | committing | closing | error` and events `apply | ok | cancel | ack | timeout | close`; actions among `"send-commit"`, `"quit"`, `"ask"`, `"show-error"`, `"start-timer"`. Rules: `ok` → committing + send-commit + start-timer; `ack` in committing (from ok) → quit; `timeout` in committing → error + show-error (no quit); `apply` → send-commit (stays idle); `cancel` → quit (helper reverts on disconnect); `close` while `unsavedChanges` → ask; `close` otherwise → quit. Timeout 3000 ms.
- `Helper.qml` (shared with the widget and the card): when `Launcher.qml` fails to load, read the port from a `--port N` pair in `Qt.application.arguments` (validated with `Net.parsePort`) before falling back to the default. Plasma behaviour unchanged. Test in `tst_net.qml` or a new case: `--port 50123` → 50123; `--port abc` → default.
- Window: `ApplicationWindow`, title `Now Playing Visualizer — Settings`, `TabBar` [Design, Audio], footer buttons Cancel / Apply / OK (Apply/OK disabled while `busy` or not connected). While `Helper` is not connected: a centred message `Can't reach the helper. Start it with: systemctl --user start nowplaying-viz` and `nowplaying-viz doctor`, pages hidden. Close prompt: `MessageDialog` "Discard the unapplied changes?".

- [ ] **Step 1:** Tests in `tst_settings_flow.qml`: `test_ok_waits_for_ack`, `test_ok_times_out_without_ack` (state `error`, actions contain `show-error`, not `quit`), `test_cancel_quits`, `test_close_with_changes_asks`, `test_apply_stays_open`.
- [ ] **Step 2:** `qmltestrunner` → FAIL.
- [ ] **Step 3:** Implement `flow.js` and `settings.qml` (window wires `DesignPage.committed` → `ack`).
- [ ] **Step 4:** `qmltestrunner` all pass; manual: `XDG_CONFIG_HOME=<scratch> NPV_PORT=<scratch port>` helper + `/usr/lib/qt6/bin/qml package/contents/settings/settings.qml -- --port <scratch port>` (backgrounded with `timeout`): window logs no QML errors, an edit + OK changes the scratch config and the window quits; with the scratch helper stopped it shows the "Can't reach the helper" state.
- [ ] **Step 5:** Commit `Settings window for desktops without Plasma`.

### Task 4: `nowplaying-viz settings` and the card's right-click

**Files:**
- Modify: `package/contents/code/cli.py` (subcommand `settings`, usage), `tools/nowplaying-viz` (usage text), `package/contents/quickshell/shell.qml` (right-click)
- Test: `tests/test_cli.py`

**Interfaces:**
- Produces: `qml_runtime() -> str | None` (first of `shutil.which("qml6")`, `shutil.which("qml")`, `/usr/lib/qt6/bin/qml` if it exists); `settings_env(env: dict) -> dict` (adds `QT_QUICK_CONTROLS_STYLE` = `org.kde.desktop` if `<qt6 qml dir>/org/kde/desktop` exists else `Fusion`, only when unset); `settings_main() -> int` → `os.execvpe(runtime, [runtime, <contents>/settings/settings.qml, "--", "--port", str(helper.PORT)], env)` (so `NPV_PORT` reaches the window); no runtime → print `No Qt QML runtime found (install qt6-declarative).` to stderr, return 1.
- Card: right-click anywhere on the card runs `python3 -I <contents>/code/cli.py settings` with `Quickshell.Io` `Process` (path from the shell's own location); left-click behaviour unchanged.

- [ ] **Step 1:** Tests: `test_settings_without_runtime` (which → None, path missing → exit 1, message, no exception), `test_settings_execs_runtime` (mock `os.execvpe`; asserts runtime, the settings.qml path and `--port <helper.PORT>`), `test_style_respects_user_choice` (env with `QT_QUICK_CONTROLS_STYLE=Material` unchanged; unset → `Fusion` when `org/kde/desktop` missing), `test_usage_lists_settings`.
- [ ] **Step 2:** `python3 -m unittest tests.test_cli` → FAIL.
- [ ] **Step 3:** Implement; shell.qml right-click.
- [ ] **Step 4:** All unit + QML tests pass; manual: `python3 -I package/contents/code/cli.py settings` opens the window (backgrounded with `timeout`, logs clean).
- [ ] **Step 5:** Commit `nowplaying-viz settings, also from the card's right-click`.

### Task 5: Launcher entry, packaging, docs, translations

**Files:**
- Create: `packaging/now-playing-visualizer-settings.desktop`
- Modify: `packaging/install.sh`, `tools/install.sh`, `tools/test-in-docker.sh` (required paths), `AGENTS.md`, `README.md`, `README.es.md`, `CHANGELOG.md` (`[Unreleased]`), `translate/template.pot`, `translate/es.po`

**Interfaces:**
- Produces: `/usr/share/applications/now-playing-visualizer-settings.desktop` (package) with the Global Constraints values; `tools/install.sh` writes `~/.local/share/applications/now-playing-visualizer-settings.desktop` with `Exec=<absolute ~/.local/bin/nowplaying-viz> settings`; `packaging/install.sh` installs the `.desktop` (644). Docs: one "Settings window" section in both READMEs and a line in AGENTS.md ("people can open `nowplaying-viz settings`; agents keep editing config.json + check"). New Plasma-visible strings (busy message) translated in `es.po`; 0 fuzzy / 0 untranslated.

- [ ] **Step 1:** Add the `.desktop` path to `required_paths` in `tools/test-in-docker.sh`; `desktop-file-validate` on the file inside the container.
- [ ] **Step 2:** Implement; `tools/extract-messages.sh`, translate, `tools/build-translations.sh`, `msgfmt --check --statistics`.
- [ ] **Step 3:** `tools/test-in-docker.sh` → all passed; unit + QML suites OK.
- [ ] **Step 4:** Commit `Settings window: launcher entry, packaging and docs`.
