// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Colour modes. paletteFor() returns the list of colours for a mode;
// makeFill() turns a list into one canvas fill (solid or gradient).
// To add a colour mode: add a case to paletteFor(), list it in isPerBar()
// if each bar gets its own colour, and add the value to schema.json.
.pragma library

function hsl(h, s, l) {
    return Qt.hsla((((h % 360) + 360) % 360) / 360, s, l, 1).toString();
}

// env: { elapsed (s), coverColors, accentColor }
function paletteFor(cfg, n, env) {
    let list;
    switch (cfg.colorMode) {
    case "hue": {
        const hue = cfg.hue;
        const shift = hue.speed * env.elapsed;
        const steps = Math.max(2, n);
        list = [];
        for (let i = 0; i < steps; i++)
            list.push(hsl(hue.start + (hue.end - hue.start) * i / (steps - 1) + shift, hue.saturation, hue.lightness));
        break;
    }
    case "cover":
        list = env.coverColors.length ? env.coverColors.slice(0, cfg.coverColorCount) : (cfg.colors || ["#ffffff"]);
        break;
    case "accent":
        list = [Qt.darker(env.accentColor, 1.3).toString(), env.accentColor.toString(), Qt.lighter(env.accentColor, 1.4).toString()];
        break;
    default:
        list = cfg.colors || ["#ffffff"];
    }
    return cfg.reverseColors ? list.slice().reverse() : list;
}

// Modes where bar i simply gets colour i (no gradient). The wave is one
// shape, so it always uses a gradient.
function isPerBar(cfg) {
    return (cfg.colorMode === "perBar" || cfg.colorMode === "hue") && cfg.style !== "wave";
}

function addStops(g, list, smooth) {
    if (list.length === 1) {
        g.addColorStop(0, list[0]);
        g.addColorStop(1, list[0]);
        return;
    }
    if (smooth) {
        list.forEach((c, i) => g.addColorStop(i / (list.length - 1), c));
    } else {
        // hard bands
        list.forEach((c, i) => {
            g.addColorStop(i / list.length, c);
            g.addColorStop(Math.min(1, (i + 1) / list.length - 0.0001), c);
        });
    }
}

// Where the conical gradient starts and ends: at the first bar, so turning
// the ring turns the colours with it. Qt measures the angle counter-clockwise
// from 3 o'clock; the ring's rotation goes clockwise from 12.
function conicalStart(cfg) {
    const rotation = cfg.circle ? cfg.circle.rotation : 0;
    return Math.PI / 2 - rotation * Math.PI / 180;
}

// One fill for the whole visualizer. geo.circle selects radial/conical.
function makeFill(ctx, list, geo, cfg, width, height) {
    if (list.length === 1)
        return list[0];
    const dir = cfg.gradient || "vertical";
    let g;
    if (geo.circle) {
        g = dir === "horizontal"
            ? ctx.createConicalGradient(geo.cx, geo.cy, conicalStart(cfg))
            : ctx.createRadialGradient(geo.cx, geo.cy, geo.inner, geo.cx, geo.cy, geo.outer);
    } else if (dir === "horizontal") {
        g = ctx.createLinearGradient(0, 0, width, 0);
    } else if (dir === "radial") {
        g = ctx.createRadialGradient(width / 2, height, 0, width / 2, height, Math.max(width, height));
    } else if (cfg.align === "center") {
        g = ctx.createLinearGradient(0, height / 2, 0, 0);
    } else if (cfg.align === "top") {
        g = ctx.createLinearGradient(0, 0, 0, height);
    } else {
        g = ctx.createLinearGradient(0, height, 0, 0);
    }
    addStops(g, list, cfg.smoothGradient);
    return g;
}
