# 002 — A small WebSocket server on Python's standard library

**Status:** accepted (supersedes the first version, which used the `websockets` package)

## Context

The first helper used the third-party `websockets` package. On Arch it comes from `python-websockets`, and its API has changed between major versions; an upgrade could stop the helper. Every Python minor upgrade also needs the package rebuilt.

## Decision

Implement the few parts of RFC 6455 we need (handshake, masked client frames, ping/pong, close, fragmented messages) on `asyncio` streams: about 100 lines in `helper.py`. Harden it at the same time:
- refuse handshakes that carry an `Origin` header (browsers always send one; Qt's client doesn't);
- refuse an unexpected `Host` (DNS rebinding);
- cap message size at 256 KB.

## Consequences

- The helper runs with only Python itself installed, so a package upgrade can't break it.
- We own a little protocol code. The tests in `tests/test_helper.py` cover the handshake rules.
- If more WebSocket features are ever needed (compression, binary frames), they have to be added by hand.
