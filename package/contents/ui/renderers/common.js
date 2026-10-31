// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Geometry shared by the renderers. Every function is pure: it gets the
// "bars" config and the canvas size and returns numbers.
.pragma library

// CAVA values are 0..1000; heightScale stretches them, the result is 0..1.
function norm(x, cfg) {
    return Math.max(0, Math.min(1, x / 1000 * cfg.heightScale));
}

// Values in drawing order: optionally reversed, optionally mirrored so the
// bass ends up in the middle.
function displayed(arr, cfg) {
    let v = cfg.reverse ? arr.slice().reverse() : arr;
    if (cfg.symmetric)
        v = v.slice().reverse().concat(v);
    return v;
}

// Horizontal slots for n bars: width per bar, gap and left offset (bars of a
// fixed width are centred).
function linearX(n, cfg, width) {
    const gap = cfg.gap;
    const bw = cfg.width > 0 ? cfg.width : Math.max(1, (width - gap * (n - 1)) / n);
    const total = n * bw + (n - 1) * gap;
    return { bw: bw, gap: gap, offset: Math.max(0, (width - total) / 2) };
}

// Top edge of a bar of height h for the configured alignment.
function spanY(h, cfg, height) {
    if (cfg.align === "center")
        return (height - h) / 2;
    if (cfg.align === "top")
        return 0;
    return height - h;
}

// Traces a curve / square / triangle line through pts.
function trace(ctx, pts, mode, move) {
    if (move)
        ctx.moveTo(pts[0].x, pts[0].y);
    else
        ctx.lineTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) {
        const p = pts[i - 1], c = pts[i];
        if (mode === "square") {
            ctx.lineTo(c.x, p.y);
            ctx.lineTo(c.x, c.y);
        } else if (mode === "triangle") {
            ctx.lineTo(c.x, c.y);
        } else {
            ctx.quadraticCurveTo(p.x, p.y, (p.x + c.x) / 2, (p.y + c.y) / 2);
            if (i === pts.length - 1)
                ctx.lineTo(c.x, c.y);
        }
    }
}

// A rectangle, rounded when r > 0.
function rect(ctx, x, y, w, h, r) {
    if (r > 0) {
        ctx.beginPath();
        ctx.roundedRect(x, y, w, h, r, r);
        ctx.fill();
    } else {
        ctx.fillRect(x, y, w, h);
    }
}
