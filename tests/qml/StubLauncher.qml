// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// Stands in for Launcher.qml in tst_helper_port.qml: records calls, starts
// nothing, and reports a port where nothing listens (never the default).
Item {
    signal portRead(string text)
    property int readPortCalls: 0
    property int launchCalls: 0

    function readPort() {
        readPortCalls++;
        portRead("50199");
    }
    function launch(path) {
        launchCalls++;
    }
}
