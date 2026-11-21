// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/tr.js" as Tr

// Outside Plasma there is no i18n, so tr.js falls back to English.
TestCase {
    name: "Tr"

    function test_substitution() {
        compare(Tr.tr("%1 of %2", "a", "b"), "a of b");
        compare(Tr.tr("Plain"), "Plain");
    }
    function test_plural() {
        compare(Tr.trp("%1 preset", "%1 presets", 1), "1 preset");
        compare(Tr.trp("%1 preset", "%1 presets", 3), "3 presets");
    }
    function test_context() {
        compare(Tr.trc("ctx", "Open"), "Open");
    }
}
