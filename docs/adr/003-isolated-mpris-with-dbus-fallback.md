# 003 — Plasma's private MPRIS module, isolated, with a D-Bus fallback

**Status:** accepted

## Context

Plasma's own media controller reads players through `org.kde.plasma.private.mpris`. It handles player selection, position tracking and `SetPosition` with the right track id, and it is already loaded in `plasmashell`. But it is private: its API can change in any Plasma release. In QML, a failing `import` stops the whole file from loading, so the entire widget would disappear.

## Decision

- Use the module, but only from `MprisSource.qml`, loaded through a `Loader`. If it fails, only that `Loader` fails.
- `main.qml` then switches to the helper, which reads MPRIS with `busctl` and offers the same actions (`mediaAction`). The same pattern protects `Launcher.qml`, which uses Plasma5Support.
- `advanced.forceDbusMedia` switches to the fallback by hand, for testing.

## Consequences

- When Plasma's module works, the widget gets its quality and efficiency.
- When it breaks, the widget keeps working, and `check.py` tells the user.
- Two code paths exist for media, and both must offer the same fields and actions (see `media` in [PROTOCOL.md](../PROTOCOL.md)).
