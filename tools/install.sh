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
dest=~/.local/share/plasma/plasmoids/com.github.mobailc.nowplayingvisualizer
if command -v kpackagetool6 >/dev/null; then
    plasma=1
    if kpackagetool6 -t Plasma/Applet -l | grep -qx com.github.mobailc.nowplayingvisualizer; then
        kpackagetool6 -t Plasma/Applet -u package
    else
        kpackagetool6 -t Plasma/Applet -i package
    fi
else
    # no Plasma (Hyprland): same path, so the systemd units work unchanged
    plasma=0
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a package/. "$dest/" # -a keeps the quickshell/ui symlink
fi
mkdir -p ~/.local/bin
install -m 755 tools/nowplaying-viz ~/.local/bin/nowplaying-viz

# the card's right-click and the launcher open this; Plasma has its own Configure…
mkdir -p ~/.local/share/applications
sed "s|^Exec=.*|Exec=$HOME/.local/bin/nowplaying-viz settings|" packaging/now-playing-visualizer-settings.desktop \
    >~/.local/share/applications/now-playing-visualizer-settings.desktop

units=~/.config/systemd/user
if [ "${1:-}" = "--systemd" ]; then
    mkdir -p "$units"
    cp packaging/systemd/* "$units/"
    if systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload
        systemctl --user enable --now nowplaying-viz.service nowplaying-viz-check.path
        systemctl --user restart nowplaying-viz.service
    else
        echo "No systemd user session here: units copied, not enabled." >&2
    fi
elif compgen -G "$units/nowplaying-viz*" >/dev/null; then
    # units from an earlier install (0.3.0's check unit runs the removed check.py):
    # refresh them, but enable nothing new
    cp packaging/systemd/* "$units/"
    if systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload
    fi
fi
# a service already running keeps the old helper until it is restarted
if systemctl --user is-active --quiet nowplaying-viz.service 2>/dev/null; then
    systemctl --user restart nowplaying-viz.service
fi
if [ "$plasma" = 1 ]; then
    echo "Done. Plasma caches widget code: log out and back in, or run 'systemctl --user restart plasma-plasmashell'."
else
    echo "Done. Add to your Hyprland config:"
    echo "  exec-once = quickshell -p $dest/contents/quickshell"
    echo "  exec-once = systemctl --user start nowplaying-viz   # starts the helper; needed without uwsm"
    echo "Then run 'nowplaying-viz doctor' (make sure ~/.local/bin is in PATH)."
fi
