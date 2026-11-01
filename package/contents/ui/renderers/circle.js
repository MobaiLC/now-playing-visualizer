// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Circular mode: the current style (bars, blocks or wave) drawn around a
// ring. See bars.js for the frame; f.geo holds the ring geometry.
.pragma library
.import "common.js" as Common

function geometry(cfg, width, height) {
    const R = Math.min(width, height) / 2;
    const inner = R * cfg.circle.size;
    return { circle: true, cx: width / 2, cy: height / 2, inner: inner, outer: R, len: R - inner };
}

// Angle of the first bar: 0° in the config is the top of the ring.
function startAngle(cfg) {
    return cfg.circle.rotation * Math.PI / 180 - Math.PI / 2;
}

// Closed line around the ring through values (the circular wave and its
// peak line); lw keeps a line of that width inside the ring.
function ringPoints(values, cfg, geo, lw) {
    const n = values.length;
    const step = 2 * Math.PI / n;
    const rot = startAngle(cfg);
    const pts = [];
    for (let i = 0; i <= n; i++) {
        const k = i % n;
        const a = rot + k * step;
        const r = geo.inner + Common.norm(values[k], cfg) * (geo.len - lw);
        pts.push({ x: geo.cx + Math.cos(a) * r, y: geo.cy + Math.sin(a) * r });
    }
    return pts;
}

// Ring sector between radii r1..r2 and angles a1..a2, filled.
function sector(ctx, geo, r1, r2, a1, a2) {
    ctx.beginPath();
    ctx.arc(geo.cx, geo.cy, r1, a1, a2, false);
    ctx.arc(geo.cx, geo.cy, r2, a2, a1, true);
    ctx.closePath();
    ctx.fill();
}

// Half the angle a bar covers, with the gap taken out.
function halfWidth(cfg, geo, n) {
    const step = 2 * Math.PI / n;
    return Math.max(0.001, (step - cfg.gap / Math.max(1, geo.inner)) / 2);
}

function draw(f) {
    const cfg = f.cfg, ctx = f.ctx, geo = f.geo;
    const n = f.v.length;
    const step = 2 * Math.PI / n;
    const rot = startAngle(cfg);
    if (cfg.style === "wave") {
        const wave = cfg.wave, lw = wave.lineWidth;
        const pts = ringPoints(f.v, cfg, geo, lw);
        ctx.beginPath();
        Common.trace(ctx, pts, wave.mode || "curve", true);
        ctx.closePath();
        if (wave.fill) {
            ctx.fillStyle = f.fill;
            ctx.globalAlpha = wave.fillOpacity;
            ctx.fill();
            ctx.globalAlpha = 1;
        }
        if (lw > 0) {
            ctx.lineWidth = lw;
            ctx.strokeStyle = f.fill;
            ctx.stroke();
        }
        return;
    }
    const bh = cfg.blocks.height, bg = cfg.blocks.gap;
    const inactive = cfg.blocks.inactive || {};
    const half = halfWidth(cfg, geo, n);
    for (let i = 0; i < n; i++) {
        const a = rot + (i + 0.5) * step;
        const len = Math.max(cfg.minHeight, Common.norm(f.v[i], cfg) * geo.len);
        const color = f.perBar ? f.colors[i % f.colors.length] : f.fill;
        if (cfg.style === "blocks") {
            const rows = Math.floor((geo.len + bg) / (bh + bg));
            const active = Math.round(len / geo.len * rows);
            for (let row = 0; row < rows; row++) {
                if (row < active)
                    ctx.fillStyle = color;
                else if (inactive.show)
                    ctx.fillStyle = inactive.color;
                else
                    break;
                const r1 = geo.inner + row * (bh + bg);
                sector(ctx, geo, r1, r1 + bh, a - half, a + half);
            }
        } else {
            ctx.fillStyle = color;
            sector(ctx, geo, geo.inner, geo.inner + len, a - half, a + half);
        }
    }
}
