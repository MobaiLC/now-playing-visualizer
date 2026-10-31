# 001 — A separate helper process, talked to over a local WebSocket

**Status:** accepted

## Context

The widget needs a continuous stream of data from `cava` (about 60 lines per second), has to manage PipeWire links, and has to watch `config.json`. Plasma widgets are QML: they can't read a child process's output line by line without a compiled C++ plugin, and a compiled plugin would have to be rebuilt for every Qt/Plasma ABI change, which is exactly the kind of breakage this project wants to avoid on a rolling distribution.

## Decision

A Python helper does the system work and serves the widget over a WebSocket on `127.0.0.1`. QML has a built-in WebSocket client (`QtWebSockets`). Every widget, and every settings page, connects to the same helper.

## Consequences

- No compiled code, so nothing to rebuild when Qt or Plasma update.
- One CAVA and one config watcher, however many widgets are open.
- A local network port exists, so it has to be protected: see [002](002-stdlib-websocket-server.md).
- The helper's lifetime has to be managed: the widget starts it on demand, it exits when idle, and a systemd service can keep it up instead.
