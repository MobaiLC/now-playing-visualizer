// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Starts helper.py when the systemd service isn't running. Loaded through a
// Loader so a change in Plasma5Support can't take the whole widget down.
P5Support.DataSource {
    engine: "executable"
    onNewData: source => disconnectSource(source)

    function launch(path) {
        connectSource(`setsid -f python3 -I '${path}' >"$HOME/.cache/nowplaying-viz.log" 2>&1`);
    }
}
