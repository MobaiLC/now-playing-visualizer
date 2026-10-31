// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Style "wave": a line through the values, optionally filled underneath
// (or mirrored around the middle). See bars.js for the frame.
.pragma library
.import "common.js" as Common

function draw(f) {
    const cfg = f.cfg, ctx = f.ctx, wave = cfg.wave;
    const n = f.v.length;
    if (n < 2)
        return;
    const lw = wave.lineWidth;
    const mode = wave.mode || "curve";
    const pts = [], low = [];
    for (let i = 0; i < n; i++) {
        const x = i * f.w / (n - 1);
        const a = Common.norm(f.v[i], cfg);
        if (cfg.align === "center") {
            pts.push({ x: x, y: f.h / 2 - a * (f.h / 2 - lw) });
            low.push({ x: x, y: f.h / 2 + a * (f.h / 2 - lw) });
        } else if (cfg.align === "top") {
            pts.push({ x: x, y: lw / 2 + a * (f.h - lw) });
        } else {
            pts.push({ x: x, y: f.h - lw / 2 - a * (f.h - lw) });
        }
    }
    if (wave.fill) {
        const fc = wave.fillColors;
        ctx.globalAlpha = wave.fillOpacity;
        ctx.beginPath();
        Common.trace(ctx, pts, mode, true);
        if (cfg.align === "center") {
            Common.trace(ctx, low.slice().reverse(), mode, false);
        } else {
            const base = cfg.align === "top" ? 0 : f.h;
            ctx.lineTo(f.w, base);
            ctx.lineTo(0, base);
        }
        ctx.closePath();
        ctx.fillStyle = fc && fc.length ? f.makeFill(fc) : f.fill;
        ctx.fill();
        ctx.globalAlpha = 1;
    }
    if (lw > 0) {
        ctx.lineWidth = lw;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.strokeStyle = f.fill;
        ctx.beginPath();
        Common.trace(ctx, pts, mode, true);
        ctx.stroke();
        if (cfg.align === "center") {
            ctx.beginPath();
            Common.trace(ctx, low, mode, true);
            ctx.stroke();
        }
    }
}
