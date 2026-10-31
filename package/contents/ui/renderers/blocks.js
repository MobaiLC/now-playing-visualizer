// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Style "blocks": each bar is a stack of blocks, like an LED meter, with
// optional unlit blocks. See bars.js for the frame passed to draw().
.pragma library
.import "common.js" as Common

function draw(f) {
    const cfg = f.cfg, ctx = f.ctx, blocks = cfg.blocks;
    const n = f.v.length;
    const L = Common.linearX(n, cfg, f.w);
    const bh = blocks.height, bg = blocks.gap;
    const center = cfg.align === "center";
    let rows = Math.max(1, Math.floor((f.h + bg) / (bh + bg)));
    if (center && rows % 2 === 0)
        rows--;
    const inactive = blocks.inactive || {};
    const r = Math.min(cfg.radius, bh / 2, L.bw / 2);
    for (let i = 0; i < n; i++) {
        const x = L.offset + i * (L.bw + L.gap);
        const active = Math.round(Common.norm(f.v[i], cfg) * rows);
        const color = f.perBar ? f.colors[i % f.colors.length] : f.fill;
        for (let row = 0; row < rows; row++) {
            let on, y;
            if (center) {
                const k = row - Math.floor(rows / 2);
                on = Math.abs(k) < Math.ceil(active / 2);
                y = f.h / 2 + k * (bh + bg) - bh / 2;
            } else if (cfg.align === "top") {
                on = row < active;
                y = row * (bh + bg);
            } else {
                on = row < active;
                y = f.h - (row + 1) * bh - row * bg;
            }
            if (on) {
                ctx.fillStyle = color;
                Common.rect(ctx, x, y, L.bw, bh, r);
            } else if (inactive.show) {
                ctx.fillStyle = inactive.color;
                Common.rect(ctx, x, y, L.bw, bh, r);
            }
        }
    }
}
