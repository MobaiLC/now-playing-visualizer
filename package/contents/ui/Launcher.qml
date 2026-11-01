// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Starts helper.py when the systemd service isn't running, and reads the
// NPV_PORT variable it will get. Loaded through a Loader so a change in
// Plasma5Support can't take the whole widget down.
P5Support.DataSource {
    id: source
    engine: "executable"

    // NPV_PORT as plasmashell (and so the helper it starts) sees it; raw
    // text, Helper.qml validates it
    signal portRead(string text)

    // a fixed command: nothing from outside is ever put into it
    readonly property string portCommand: "printf '%s' \"${NPV_PORT-}\""

    onNewData: (name, data) => {
        if (name === portCommand)
            portRead(String(data.stdout || ""));
        disconnectSource(name);
    }

    function readPort() {
        connectSource(portCommand);
    }

    function launch(path) {
        // single-quote the path for the shell, whatever it contains
        const quoted = "'" + path.replace(/'/g, "'\\''") + "'";
        connectSource(`setsid -f python3 -I ${quoted} >"$HOME/.cache/nowplaying-viz.log" 2>&1`);
    }
}
