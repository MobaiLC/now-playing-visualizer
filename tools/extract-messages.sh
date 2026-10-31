#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Collects every translatable string into translate/template.pot and updates
# each translate/<lang>.po. Run it after adding or changing UI text.
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="plasma_applet_com.github.mobailc.nowplayingvisualizer"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# schema.json labels are only known at runtime; turn them into i18n() calls
# so xgettext can see them.
python3 -I - package/contents/code/schema.json > "$tmp/schema-strings.js" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
labels = [g["label"] for g in schema["groups"]]
for spec in schema["options"].values():
    labels.append(spec["label"])
    labels += [v["label"] for v in spec.get("values", [])]
    if "autoLabel" in spec:
        labels.append(spec["autoLabel"])
for label in dict.fromkeys(labels):
    print("i18n(%s);" % json.dumps(label))
PY

find package -name '*.qml' | sort > "$tmp/qml.txt"
xgettext --from-code=UTF-8 -C -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
    --package-name="Now Playing Visualizer" --msgid-bugs-address="https://github.com/MobaiLC/now-playing-visualizer/issues" \
    -L JavaScript -o "$tmp/qml.pot" -f "$tmp/qml.txt" "$tmp/schema-strings.js"
xgettext --from-code=UTF-8 -L Python -k_ -o "$tmp/py.pot" package/contents/code/check.py
msgcat --use-first "$tmp/qml.pot" "$tmp/py.pot" -o translate/template.pot
sed -i "s/charset=CHARSET/charset=UTF-8/" translate/template.pot

for po in translate/*.po; do
    [ -e "$po" ] || continue
    msgmerge --quiet --update --backup=none "$po" translate/template.pot
    echo "updated $po"
done
echo "template: translate/template.pot ($(grep -c '^msgid' translate/template.pot) strings)"
