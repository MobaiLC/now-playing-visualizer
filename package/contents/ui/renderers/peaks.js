// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Falling peak markers on top of linear bars and blocks. See bars.js for the
// frame; f.peaks holds the peak values.
.pragma library
.import "common.js" as Common

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
