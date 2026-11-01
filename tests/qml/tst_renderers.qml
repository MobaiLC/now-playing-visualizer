// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/renderers/common.js" as Common
import "../../package/contents/ui/renderers/palette.js" as Palette
import "../../package/contents/ui/renderers/circle.js" as Circle
import "../../package/contents/ui/renderers/registry.js" as Renderers

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

    function test_conical_gradient_starts_at_the_first_bar() {
        // Qt counts counter-clockwise from 3 o'clock; the ring starts at 12
        fuzzyCompare(Palette.conicalStart({ circle: { rotation: 0 } }), Math.PI / 2, 1e-9);
        fuzzyCompare(Palette.conicalStart({ circle: { rotation: 90 } }), 0, 1e-9);
        fuzzyCompare(Palette.conicalStart({}), Math.PI / 2, 1e-9);
    }

    function test_wave_points() {
        const cfg = { heightScale: 1, align: "bottom" };
        const p = Common.wavePoints([0, 1000], cfg, 100, 50, 2);
        compare(p.pts.length, 2);
        compare(p.pts[0].x, 0);
        compare(p.pts[1].x, 100);
        compare(p.pts[0].y, 49);
        compare(p.pts[1].y, 1);
        compare(p.low.length, 0);
        compare(Common.wavePoints([500, 500], { heightScale: 1, align: "center" }, 100, 50, 0).low.length, 2);
    }

    function test_ring_points_close_the_loop() {
        const geo = Circle.geometry({ circle: { size: 0.5 } }, 100, 100);
        const pts = Circle.ringPoints([0, 500, 1000, 500], { heightScale: 1, circle: { rotation: 0 } }, geo, 0);
        compare(pts.length, 5);
        fuzzyCompare(pts[0].x, pts[4].x, 1e-9);
        fuzzyCompare(pts[0].y, pts[4].y, 1e-9);
        // first point at the top of the ring, on the inner radius (value 0)
        fuzzyCompare(pts[0].x, 50, 1e-9);
        fuzzyCompare(pts[0].y, 50 - geo.inner, 1e-9);
    }

    // A context that accepts every call the renderers make and counts them.
    function fakeContext() {
        const ctx = { calls: 0, globalAlpha: 1 };
        for (const name of ["beginPath", "closePath", "moveTo", "lineTo", "quadraticCurveTo", "arc", "fill",
                            "stroke", "fillRect", "roundedRect", "addColorStop"])
            ctx[name] = function () { ctx.calls++; };
        return ctx;
    }

    function config(style, circle, peaks) {
        return {
            style: style, count: 16, gap: 2, width: 0, radius: 2, align: "bottom", minHeight: 2, heightScale: 1,
            reverse: false, symmetric: false,
            circle: { enabled: circle, size: 0.45, rotation: 30 },
            blocks: { height: 4, gap: 2, inactive: { show: true, color: "#ffffff1a" } },
            wave: { mode: "curve", lineWidth: 2, fill: true, fillOpacity: 0.3, fillColors: [] },
            peaks: { enabled: peaks, color: "", height: 2 }
        };
    }

    function test_every_style_draws_with_and_without_peaks_data() {
        const rows = [];
        for (const style of ["bars", "blocks", "wave"])
            for (const circle of [false, true])
                for (const peaks of [false, true])
                    rows.push({ tag: style + (circle ? " circular" : "") + (peaks ? " + peaks" : ""),
                                style: style, circle: circle, peaks: peaks });
        return rows;
    }
    function test_every_style_draws_with_and_without_peaks(data) {
        const cfg = config(data.style, data.circle, data.peaks);
        const v = [100, 400, 900, 300, 700, 50, 1000, 600, 200, 800, 450, 350, 650, 150, 950, 500];
        const peaks = v.map(x => Math.min(1000, x + 100));
        const draw = c => {
            const ctx = fakeContext();
            const geo = data.circle ? Circle.geometry(c, 200, 100) : { circle: false };
            Renderers.draw({ ctx: ctx, w: 200, h: 100, cfg: c, geo: geo, v: v, peaks: peaks,
                             colors: ["#ffffff"], perBar: false, fill: "#ffffff", makeFill: list => list[0] });
            return ctx.calls;
        };
        const calls = draw(cfg);
        verify(calls > 0);
        if (data.peaks) {
            const without = draw(config(data.style, data.circle, false));
            verify(calls > without, calls + " <= " + without);
        }
    }
}
