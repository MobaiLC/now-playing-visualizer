# 006 — schema.json as the single source of truth for options

**Status:** accepted

## Context

In the first version, every option had its default written in three places: `presets.json`, `?? fallback` expressions in the QML, and the hand-written Design page. Adding an option meant touching all three, and they had already started to drift.

## Decision

`code/schema.json` describes every option: type, default, range, unit, label, group, tab, and `when` / `whenNot` visibility. From it:
- the helper builds the defaults and validates every config (invalid → default, out of range → clamped, both reported);
- the Design page builds its controls (one QML component per type);
- `tools/gen-config-doc.py` writes `docs/CONFIG.md`, and CI fails if that file is stale;
- `tools/extract-messages.sh` extracts the labels for translation.

The widget's QML reads values without fallbacks, because the helper always sends every key.

## Consequences

- Adding an option means adding a schema entry, then using it in QML.
- QML must not add its own defaults again; a missing key is a bug in the schema.
- Renaming an option needs a migration step in `migrate()` and a bump of `version` in both `schema.json` and `CONFIG_VERSION`. A test checks that the two match.
