// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/players.js" as Players

// Which player the widget shows and what its menu lists; the same rules as
// pick_player() in helper.py (tests/test_helper.py checks that side).
TestCase {
    name: "Players"

    readonly property var spotify: ({ identity: "Spotify", desktopEntry: "spotify", playing: true })
    readonly property var zen: ({ identity: "Zen", desktopEntry: "zen", playing: false })
    readonly property var liner: ({ identity: "Liner", desktopEntry: "liner", playing: false })

    function test_pinned_wins_while_open() {
        compare(Players.pick([spotify, zen], "Zen", []), zen);
        compare(Players.pick([spotify, zen], "zen", []), zen);
    }

    function test_automatic_order() {
        compare(Players.pick([zen, spotify], "", []), spotify);
        compare(Players.pick([zen, liner], "", ["liner"]), liner);
        compare(Players.pick([zen, liner], "", []), zen);
        compare(Players.pick([], "", []), null);
    }

    function test_closed_pin_falls_back() {
        compare(Players.pick([zen, spotify], "Liner", []), spotify);
    }

    function test_pinned_is_exact() {
        const nightly = { identity: "Zen Browser Nightly", playing: true };
        compare(Players.pick([nightly, liner], "Zen", []), nightly);
        compare(Players.pick([liner, nightly], "Zen", []), nightly);
    }

    function test_widget_keeps_plasmas_current_player_as_last_resort() {
        // MprisSource.qml passes orFirst = false and then uses mpris.currentPlayer
        compare(Players.pick([zen, liner], "", [], false), null);
        compare(Players.pick([zen, liner], "Liner", [], false), liner);
    }

    function test_empty_preferred_entries_match_nothing() {
        compare(Players.pick([zen, liner], "", [""], false), null);
    }

    function test_menu_lists_each_player_once() {
        const zen2 = { identity: "Zen", playing: true };
        compare(Players.menu([spotify, zen, zen2], ""), [
            { identity: "Spotify", open: true, playing: true },
            { identity: "Zen", open: true, playing: false }
        ]);
    }

    function test_menu_keeps_a_closed_pin_so_it_can_be_undone() {
        compare(Players.menu([spotify], "Liner"), [
            { identity: "Spotify", open: true, playing: true },
            { identity: "Liner", open: false, playing: false }
        ]);
        compare(Players.menu([spotify], "spotify").length, 1);
        compare(Players.menu([{ identity: "", playing: true }], ""), []);
    }

    function test_repeat_cycles() {
        compare(Players.nextLoop("None"), "Playlist");
        compare(Players.nextLoop("Playlist"), "Track");
        compare(Players.nextLoop("Track"), "None");
        compare(Players.nextLoop(null), "None");
    }
}
