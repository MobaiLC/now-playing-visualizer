# Architecture decision records

Short notes on *why* things are the way they are. Read the relevant one before undoing a decision; if you change one, add a new record that supersedes it instead of editing history.

| # | Decision |
|---|---|
| [001](001-helper-over-websocket.md) | A separate helper process, talked to over a local WebSocket |
| [002](002-stdlib-websocket-server.md) | A small WebSocket server on Python's standard library |
| [003](003-isolated-mpris-with-dbus-fallback.md) | Plasma's private MPRIS module, isolated, with a D-Bus fallback |
| [004](004-per-app-audio-by-linking-into-cava.md) | Per-app audio by linking apps straight into CAVA |
| [005](005-live-edit-with-revert.md) | Live editing that Cancel can revert |
| [006](006-schema-as-single-source-of-truth.md) | schema.json as the single source of truth for options |
