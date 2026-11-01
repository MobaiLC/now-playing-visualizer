// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest

// MprisSource.qml with Plasma's real MPRIS module, against the fake players
// of run.sh on a private session bus. Skipped when the module isn't there
// (it comes with plasma-workspace).
TestCase {
    id: tc
    name: "MprisSource"
    when: windowShown

    property var source: null

    function initTestCase() {
        const c = Qt.createComponent("../../package/contents/ui/MprisSource.qml");
        if (c.status !== Component.Ready)
            skip("Plasma's MPRIS module is not installed: " + c.errorString());
        source = c.createObject(tc);
        tryVerify(() => source.playerList.length >= 3, 10000, "the fake players show up");
    }

    function cleanupTestCase() {
        if (source)
            source.destroy();
    }

    function init() {
        source.pinned = "";
    }

    function test_lists_every_player() {
        const names = source.playerList.map(p => p.identity);
        verify(names.includes("Spotifake"), names);
        verify(names.includes("Zenfake"), names);
        verify(names.includes("Lockedfake"), names);
    }

    function test_automatic_pick_is_the_playing_one() {
        tryCompare(source.media, "identity", "Spotifake");
    }

    function test_pinned_player_is_shown() {
        source.pinned = "Zenfake";
        tryVerify(() => source.media && source.media.identity === "Zenfake");
        source.pinned = "Not Open";
        tryVerify(() => source.media && source.media.identity === "Spotifake");
    }

    function test_no_shuffle_or_repeat_when_the_player_has_none() {
        source.pinned = "Zenfake";
        tryVerify(() => source.media && source.media.identity === "Zenfake");
        compare(source.media.shuffle, null);
        compare(source.media.loop, null);
    }

    function test_shuffle_and_repeat_round_trip() {
        source.pinned = "Spotifake";
        tryVerify(() => source.media && source.media.identity === "Spotifake");
        compare(source.media.shuffle, false);
        compare(source.media.loop, "None");
        source.act("shuffle", true);
        tryVerify(() => source.media.shuffle === true, 5000, "shuffle on");
        source.act("loop", "Track");
        tryVerify(() => source.media.loop === "Track", 5000, "repeat track");
        source.act("loop", "None");
        source.act("shuffle", false);
        tryVerify(() => source.media.shuffle === false && source.media.loop === "None", 5000, "back off");
    }

    function test_bad_values_are_ignored() {
        source.pinned = "Spotifake";
        tryVerify(() => source.media && source.media.identity === "Spotifake");
        source.act("loop", "Forever");
        source.act("shuffle", "yes");
        wait(500);
        compare(source.media.loop, "None");
        compare(source.media.shuffle, false);
    }
}
