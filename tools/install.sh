#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs (or updates) the widget for the current user.
#   tools/install.sh            widget only
#   tools/install.sh --systemd  also the helper service and the post-update check
set -euo pipefail
cd "$(dirname "$0")/.."

tools/build-translations.sh
if kpackagetool6 -t Plasma/Applet -l | grep -qx com.github.mobailc.nowplayingvisualizer; then
    kpackagetool6 -t Plasma/Applet -u package
else
    kpackagetool6 -t Plasma/Applet -i package
fi

if [ "${1:-}" = "--systemd" ]; then
    mkdir -p ~/.config/systemd/user
    cp packaging/systemd/* ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now nowplaying-viz.service nowplaying-viz-check.path
    systemctl --user restart nowplaying-viz.service
fi
# a service already running keeps the old helper until it is restarted
if systemctl --user is-active --quiet nowplaying-viz.service 2>/dev/null; then
    systemctl --user restart nowplaying-viz.service
fi
echo "Done. Plasma caches widget code: log out and back in, or run 'systemctl --user restart plasma-plasmashell'."
