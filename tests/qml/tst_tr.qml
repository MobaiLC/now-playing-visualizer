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
        compare(Tr.tr("%1%10", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j"), "aj");
        compare(Tr.tr("%2 kept", "a"), "%2 kept");
    }
    function test_plural() {
        compare(Tr.trp("%1 preset", "%1 presets", 1), "1 preset");
        compare(Tr.trp("%1 preset", "%1 presets", 3), "3 presets");
        compare(Tr.trp("%1 file in %2", "%1 files in %2", "1", "x"), "1 file in x");
        compare(Tr.trp("%1 file in %2", "%1 files in %2", 2, "x"), "2 files in x");
    }
    function test_context() {
        compare(Tr.trc("ctx", "Open"), "Open");
    }
}
