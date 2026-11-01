// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest

// Every QML file of the widget must compile. Plasma only reports a broken
// file when it loads the widget ("Type Card unavailable"), and qmllint
// misses some errors, like overriding a FINAL property of Kirigami.Icon.
// A file whose imports aren't installed here (Plasma, Kirigami) is skipped,
// not failed; CI installs them.
TestCase {
    name: "Components"

    function test_compiles_data() {
        return ["main.qml", "Card.qml", "Bars.qml", "Helper.qml", "Launcher.qml", "MprisSource.qml",
                "configDesign.qml", "configApps.qml"].map(f => ({ tag: f, file: f }));
    }
    function test_compiles(data) {
        const c = Qt.createComponent("../../package/contents/ui/" + data.file);
        if (c.status === Component.Loading)
            tryVerify(() => c.status !== Component.Loading);
        const error = c.errorString();
        if (c.status === Component.Error && /module "[^"]+" is not installed/.test(error))
            skip(error.trim());
        verify(c.status === Component.Ready, error);
    }
}
