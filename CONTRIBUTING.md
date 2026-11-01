# Contributing

Thanks for helping! Bug reports, presets, translations and code are all welcome. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first; it's short.

## Set up

```bash
git clone https://github.com/MobaiLC/now-playing-visualizer.git
cd now-playing-visualizer
tools/install.sh                                   # installs the working copy
systemctl --user restart plasma-plasmashell        # Plasma caches widget code
```

After every change: `tools/install.sh`, then restart Plasma (for QML) or the helper (`systemctl --user restart nowplaying-viz`, or kill it and let the widget start it again).

Useful while working:
- `QT_FORCE_STDERR_LOGGING=1 /usr/lib/qt6/bin/qml file.qml`: runs a QML test file with warnings on the terminal. Without that variable they go to the journal.
- `journalctl --user -u plasma-plasmashell -f | grep nowplayingvisualizer`: warnings from the installed widget.
- `NPV_PORT=47899 XDG_CONFIG_HOME=/tmp/npv python3 package/contents/code/helper.py`: a second helper with its own port and config, so you can test without touching your real one.

## Before sending a pull request

```bash
python3 -m unittest discover -s tests -v      # helper tests
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml   # QML/JS tests
python3 tools/gen-config-doc.py --check       # docs/CONFIG.md matches schema.json
tools/extract-messages.sh                      # if you changed any UI text
msgfmt --check -o /dev/null translate/*.po
```

The QML tests cover the pure parts (`ui/net.js`, `ui/renderers/`); keep new logic there, out of the `.qml` files, so it can be tested. CI runs the same checks. In the PR, say how you tested the change, and what you couldn't test.

## Recipes

### Add an option

1. Add an entry to `package/contents/code/schema.json`:
   ```json
   "bars.example": { "group": "bars", "type": "bool", "default": false, "label": "Example" }
   ```
   The types are `bool`, `int`, `real`, `enum`, `color`, `colorOrAuto`, `colorList`, `string` and `stringList`. Use `when` / `whenNot` to show it only when it applies.
2. Read it in QML as `cfg.bars.example`, with no `??` fallback: the helper always sends every key.
3. Run `python3 tools/gen-config-doc.py` and `tools/extract-messages.sh`, then translate the new label in `translate/es.po`.

The Design page and validation pick it up by themselves.

### Rename or remove an option

Add a step to `migrate()` in `helper.py`, then bump `CONFIG_VERSION` there and `version` in `schema.json`; a test checks that the two match. Otherwise users' saved settings silently stop applying.

### Add a bar style

1. Create `package/contents/ui/renderers/<style>.js` with `.pragma library` and a `draw(f)` function. The frame `f` is documented at the top of `bars.js`.
2. Import it in `renderers/registry.js` and add it to `styles`.
3. Add the value to `bars.style` in `schema.json`.

### Add a colour mode

Add a case to `paletteFor()` in `renderers/palette.js`. If each bar gets its own colour, list the mode in `isPerBar()` too. Then add the value to `bars.colorMode` in `schema.json`.

### Add a preset

Create `package/contents/code/presets/<name>.json` listing only what differs from the defaults, for example:
```json
{ "bars": { "colors": ["#ff4fd8", "#38e8ff"], "glow": { "enabled": true } } }
```
The tests check that every preset uses only valid options.

### Translate

Copy `translate/template.pot` to `translate/<lang>.po`, translate it (Lokalize or Poedit work well), and run `tools/install.sh`.

## Style

- **QML:** 4-space indent and Kirigami units for spacing. Comments explain *why*, not what.
- **Python:** standard library only (see [ADR 002](docs/adr/002-stdlib-websocket-server.md)).
- **New files** start with an SPDX header (`GPL-3.0-or-later`).
- **Text from players** (titles, app names) is never rendered as rich text: use `textFormat: Text.PlainText`.

## Decisions

If your change goes against one of the [architecture decision records](docs/adr/README.md), add a new record explaining why.
