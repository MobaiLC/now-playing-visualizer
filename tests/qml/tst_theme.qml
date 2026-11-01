// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/theme.js" as Theme

// Card colours from the cover art: always readable.
TestCase {
    name: "Theme"

    function test_contrast_matches_wcag() {
        fuzzyCompare(Theme.contrast("#000000", "#ffffff"), 21, 0.01);
        fuzzyCompare(Theme.contrast("#777777", "#777777"), 1, 0.001);
        // a classic reference pair: #767676 on white is just over 4.5:1
        verify(Theme.contrast("#767676", "#ffffff") >= 4.5);
        verify(Theme.contrast("#777777", "#ffffff") < 4.5);
    }

    function test_text_is_white_on_dark_and_dark_on_light() {
        compare(Theme.textOn("#101020"), "#ffffff");
        compare(Theme.textOn("#f4ecd0"), "#111111");
    }

    function test_text_always_reaches_the_minimum_data() {
        return [
            { tag: "black", bg: "#000000" }, { tag: "white", bg: "#ffffff" },
            { tag: "mid grey", bg: "#777777" }, { tag: "pure red", bg: "#ff0000" },
            { tag: "pure yellow", bg: "#ffff00" }, { tag: "pure blue", bg: "#0000ff" },
        ];
    }
    function test_text_always_reaches_the_minimum(data) {
        verify(Theme.contrast(Theme.textOn(data.bg), data.bg) >= Theme.TEXT_CONTRAST,
               Theme.contrast(Theme.textOn(data.bg), data.bg));
    }

    function test_accent_is_nudged_until_it_stands_out() {
        const bg = "#14141e";
        // a dark purple on a dark background: lightened
        const accent = Theme.accentOn("#3a2050", bg);
        verify(Theme.contrast(accent, bg) >= Theme.ACCENT_CONTRAST);
        // a colour that already stands out is kept
        compare(Theme.accentOn("#ff4fd8", bg).toString(), Qt.color("#ff4fd8").toString());
    }

    function test_cover_colours_are_readable_data() {
        return [
            { tag: "vivid", vivid: ["#ff3c78", "#28c8ff"], main: "#ff3c78" },
            { tag: "light", vivid: ["#c87840", "#f4ecd0"], main: "#f4ecd0" },
            { tag: "dark", vivid: ["#3c1e5a", "#121428"], main: "#121428" },
            { tag: "white", vivid: ["#ffffff"], main: "#ffffff" },
            { tag: "black", vivid: ["#000000"], main: "#000000" },
        ];
    }
    function test_cover_colours_are_readable(data) {
        for (const backdrop of [null, { average: data.main, dim: 0.6 }, { average: "#ffffff", dim: 0.3 }]) {
            const t = Theme.fromCover(data.vivid, data.main, 0.66, backdrop);
            const under = Theme.behindText(Qt.rgba(t.background.r, t.background.g, t.background.b, 1), backdrop);
            verify(Theme.contrast(t.title, under) >= Theme.TEXT_CONTRAST, "title " + Theme.contrast(t.title, under));
            verify(Theme.contrast(t.progress, under) >= Theme.ACCENT_CONTRAST, "progress " + Theme.contrast(t.progress, under));
        }
    }

    function test_background_keeps_the_users_opacity() {
        fuzzyCompare(Theme.fromCover(["#ff3c78"], "#ff3c78", 0.66, null).background.a, 0.66, 0.01);
    }

    function test_nothing_to_use_gives_null() {
        compare(Theme.fromCover([], "#ff3c78", 1, null), null);
        compare(Theme.fromCover(undefined, "#ff3c78", 1, null), null);
        compare(Theme.fromCover(["#ff3c78"], "", 1, null), null);
    }
}
