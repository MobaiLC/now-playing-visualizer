# 005 — Live editing that Cancel can revert

**Status:** accepted

## Context

Seeing changes immediately on the widget and in the preview is the best experience. But in Plasma's settings dialog, **Cancel** is expected to discard changes, and the first version had none: every change was saved at once. Plasma's dialog offers `unsavedChanges` and `saveConfig()` to pages, but no hook for Cancel.

## Decision

The helper keeps an **edit session** for the Design page:
- `beginEdit` takes a snapshot of the design keys (`preset`, `overrides`, `presets`).
- Changes still apply live; each one pushes the previous state onto an Undo history.
- `saveConfig()` (Apply/OK) sends `commitEdit`, and also bumps the plasmoid setting `designCommit`, which `main.qml` forwards as another `commitEdit`.
- When the page disconnects without a commit, the helper waits 1.5 s and restores the snapshot.

## Consequences

- Cancel, closing the window, and even a crash of the dialog all revert.
- OK closes the dialog before calling `saveConfig()`, and the page's socket may close first; the second commit path through `designCommit` covers that, within the 1.5 s grace period.
- The Audio page is not part of the session: like a normal toggle, it saves at once.
- Covered by `DesignEditTests` and by a manual test of cancel, undo, apply and OK against a test helper.
