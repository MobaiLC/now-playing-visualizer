// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Style "bars": one rectangle per value.
//
// Every renderer exports draw(f), where f is the frame built by Bars.qml:
//   f.ctx     canvas 2D context        f.w, f.h  canvas size
//   f.cfg     the "bars" config        f.v       values to draw (0..1000)
//   f.peaks   peak values              f.colors  palette for the colour mode
//   f.fill    shared solid/gradient    f.perBar  true: bar i uses f.colors[i]
//   f.geo     circle geometry (circular mode only)
//   f.makeFill(list)  builds a fill from another colour list
.pragma library
.import "common.js" as Common

function draw(f) {
    const cfg = f.cfg, ctx = f.ctx;
    const n = f.v.length;
    const L = Common.linearX(n, cfg, f.w);
    for (let i = 0; i < n; i++) {
        const h = Math.max(cfg.minHeight, Common.norm(f.v[i], cfg) * f.h);
        const x = L.offset + i * (L.bw + L.gap);
        ctx.fillStyle = f.perBar ? f.colors[i % f.colors.length] : f.fill;
        Common.rect(ctx, x, Common.spanY(h, cfg, f.h), L.bw, h, Math.min(cfg.radius, L.bw / 2, h / 2));
    }
}
