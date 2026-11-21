#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs everything a system package ships into DESTDIR (both AUR PKGBUILDs
# call it from package()). Run tools/build-translations.sh first.
#
#   packaging/install.sh "$pkgdir"
set -euo pipefail
cd "$(dirname "$0")/.."

dest=${1:?usage: packaging/install.sh DESTDIR}
id=com.github.mobailc.nowplayingvisualizer
plasmoid="$dest/usr/share/plasma/plasmoids/$id"

install -d "$plasmoid"
# cp -r keeps contents/quickshell/ui as its relative symlink to ../ui
cp -r package/. "$plasmoid/"
find "$plasmoid" -name __pycache__ -type d -prune -exec rm -rf {} +
install -d "$plasmoid/contents/skill"
cat packaging/skill-frontmatter.md AGENTS.md > "$plasmoid/contents/skill/SKILL.md"
chmod 644 "$plasmoid/contents/skill/SKILL.md"
# the path AGENTS.md and quickshell -p use
ln -s "plasma/plasmoids/$id/contents" "$dest/usr/share/now-playing-visualizer"

# the units in the repo point at a per-user install; point them here instead
for unit in packaging/systemd/*; do
    sed "s|%h/.local/share/plasma/plasmoids|/usr/share/plasma/plasmoids|" "$unit" \
        | install -Dm644 /dev/stdin "$dest/usr/lib/systemd/user/$(basename "$unit")"
done

install -Dm755 tools/nowplaying-viz "$dest/usr/bin/nowplaying-viz"
install -Dm644 -t "$dest/usr/share/doc/now-playing-visualizer" README.md AGENTS.md docs/CONFIG.md
install -Dm644 LICENSE "$dest/usr/share/licenses/now-playing-visualizer/LICENSE"
