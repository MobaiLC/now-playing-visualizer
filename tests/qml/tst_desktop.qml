// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/desktop.js" as Desktop

// Where the quickshell card goes: which screen and which corner.
TestCase {
    name: "Desktop"

    readonly property var screens: [{ name: "DP-1" }, { name: "HDMI-A-1" }]

    function test_pick_screen_by_name() {
        compare(Desktop.pickScreen(screens, "HDMI-A-1").name, "HDMI-A-1");
    }

    function test_pick_screen_falls_back() {
        compare(Desktop.pickScreen(screens, "DP-9").name, "DP-1");
        compare(Desktop.pickScreen(screens, "").name, "DP-1");
        compare(Desktop.pickScreen([], "DP-1"), null);
    }

    function test_anchors() {
        const bottomRight = { top: false, bottom: true, left: false, right: true };
        compare(Desktop.anchorsFor("bottomRight"), bottomRight);
        compare(Desktop.anchorsFor("nonsense"), bottomRight);
        compare(Desktop.anchorsFor("topLeft"), { top: true, bottom: false, left: true, right: false });
    }
}
