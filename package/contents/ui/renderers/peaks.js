// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Falling peak markers: a mark over each bar or block (draw), a thin line
// over the wave (drawWave) and both around the ring (drawCircle). See
// bars.js for the frame; f.peaks holds the peak values.
.pragma library
.import "common.js" as Common
.import "circle.js" as Circle

function colorOf(f) {
    return f.cfg.peaks.color || f.fill;
}

// A line through the peaks, mapped like the wave so it sits right over it.
function stroke(ctx, pts, mode, width) {
    ctx.lineWidth = width;
    ctx.lineJoin = "round";
    ctx.lineCap = "round";
    ctx.beginPath();
    Common.trace(ctx, pts, mode, true);
    ctx.stroke();
}

function drawWave(f) {
    const cfg = f.cfg, ctx = f.ctx;
    if (f.peaks.length < 2)
        return;
    const p = Common.wavePoints(f.peaks, cfg, f.w, f.h, cfg.wave.lineWidth);
    const mode = cfg.wave.mode || "curve";
    ctx.strokeStyle = colorOf(f);
    stroke(ctx, p.pts, mode, cfg.peaks.height);
    if (cfg.align === "center")
        stroke(ctx, p.low, mode, cfg.peaks.height);
}

function drawCircle(f) {
    const cfg = f.cfg, ctx = f.ctx, geo = f.geo;
    const n = f.peaks.length;
    if (!n)
        return;
    const ph = cfg.peaks.height;
    if (cfg.style === "wave") {
        ctx.strokeStyle = colorOf(f);
        stroke(ctx, Circle.ringPoints(f.peaks, cfg, geo, cfg.wave.lineWidth), cfg.wave.mode || "curve", ph);
        return;
    }
    const own = cfg.peaks.color || "";
    const step = 2 * Math.PI / n;
    const rot = Circle.startAngle(cfg);
    const half = Circle.halfWidth(cfg, geo, n);
    ctx.fillStyle = own || f.fill;
    for (let i = 0; i < n; i++) {
        const len = Common.norm(f.peaks[i], cfg) * geo.len;
        if (len < 1)
            continue;
        if (f.perBar && !own)
            ctx.fillStyle = f.colors[i % f.colors.length];
        const a = rot + (i + 0.5) * step;
        const r = Math.min(geo.inner + len + 1, geo.outer - ph);
        Circle.sector(ctx, geo, r, r + ph, a - half, a + half);
    }
}

function draw(f) {
    const cfg = f.cfg, ctx = f.ctx;
    const n = f.peaks.length;
    const L = Common.linearX(n, cfg, f.w);
    const ph = cfg.peaks.height;
    const own = cfg.peaks.color || "";
    ctx.fillStyle = own || f.fill;
    for (let i = 0; i < n; i++) {
        const h = Common.norm(f.peaks[i], cfg) * f.h;
        if (h < 1)
            continue;
        if (f.perBar && !own)
            ctx.fillStyle = f.colors[i % f.colors.length];
        const x = L.offset + i * (L.bw + L.gap);
        if (cfg.align === "center") {
            ctx.fillRect(x, (f.h - h) / 2 - ph - 1, L.bw, ph);
            ctx.fillRect(x, (f.h + h) / 2 + 1, L.bw, ph);
        } else if (cfg.align === "top") {
            ctx.fillRect(x, h + 1, L.bw, ph);
        } else {
            ctx.fillRect(x, f.h - h - ph - 1, L.bw, ph);
        }
    }
}
