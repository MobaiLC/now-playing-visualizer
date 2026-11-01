// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/renderers/common.js" as Common
import "../../package/contents/ui/renderers/palette.js" as Palette

// The pure parts of the renderers: geometry and colour modes.
TestCase {
    name: "Renderers"

    function test_norm_clamps_to_0_1() {
        compare(Common.norm(500, { heightScale: 1 }), 0.5);
        compare(Common.norm(800, { heightScale: 2 }), 1);
        compare(Common.norm(-10, { heightScale: 1 }), 0);
    }

    function test_displayed_order() {
        compare(Common.displayed([1, 2, 3], {}), [1, 2, 3]);
        compare(Common.displayed([1, 2, 3], { reverse: true }), [3, 2, 1]);
        compare(Common.displayed([1, 2, 3], { symmetric: true }), [3, 2, 1, 1, 2, 3]);
    }

    function test_displayed_leaves_input_alone() {
        const v = [1, 2, 3];
        Common.displayed(v, { reverse: true, symmetric: true });
        compare(v, [1, 2, 3]);
    }

    function test_automatic_and_fixed_bar_width() {
        const auto = Common.linearX(4, { gap: 4, width: 0 }, 100);
        compare(auto.bw, 22);
        compare(auto.offset, 0);
        const fixed = Common.linearX(4, { gap: 4, width: 10 }, 100);
        compare(fixed.bw, 10);
        compare(fixed.offset, 24);
    }

    function test_alignment() {
        compare(Common.spanY(20, { align: "bottom" }, 100), 80);
        compare(Common.spanY(20, { align: "top" }, 100), 0);
        compare(Common.spanY(20, { align: "center" }, 100), 40);
    }

    function test_cover_mode_without_cover_uses_the_colours() {
        const cfg = { colorMode: "cover", coverColorCount: 3, colors: ["#ff0000"] };
        compare(Palette.paletteFor(cfg, 8, { elapsed: 0, coverColors: [], accentColor: "#3daee9" }), ["#ff0000"]);
        compare(Palette.paletteFor(cfg, 8, { elapsed: 0, coverColors: ["#111111", "#222222", "#333333", "#444444"], accentColor: "#3daee9" }),
                ["#111111", "#222222", "#333333"]);
    }

    function test_hue_gives_one_colour_per_bar() {
        const cfg = { colorMode: "hue", hue: { start: 0, end: 360, saturation: 1, lightness: 0.5, speed: 0 } };
        compare(Palette.paletteFor(cfg, 12, { elapsed: 0, coverColors: [], accentColor: "#3daee9" }).length, 12);
    }

    function test_reverse_colours() {
        const cfg = { colorMode: "gradient", colors: ["#111111", "#222222"], reverseColors: true };
        compare(Palette.paletteFor(cfg, 4, { elapsed: 0, coverColors: [], accentColor: "#3daee9" }), ["#222222", "#111111"]);
        compare(cfg.colors, ["#111111", "#222222"]);
    }

    function test_wave_never_uses_per_bar_colours() {
        verify(Palette.isPerBar({ colorMode: "perBar", style: "bars" }));
        verify(!Palette.isPerBar({ colorMode: "perBar", style: "wave" }));
        verify(!Palette.isPerBar({ colorMode: "gradient", style: "bars" }));
    }
}
