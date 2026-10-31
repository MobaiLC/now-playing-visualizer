// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Effects

// Spectrum drawn on a Canvas: bars, blocks or wave, linear or circular,
// with several colour modes, falling peaks and optional glow.
Item {
    id: root

    // always the full "bars" object from the helper; empty only while being created
    property var cfg: ({})
    property var targets: []
    property var coverColors: []
    // false = draw targets as they are, once (preset thumbnails)
    property bool live: true
    property color accentColor: "#3daee9"

    property var shown: []
    property var peaks: []
    property var peakHold: []
    property bool silent: true
    property real elapsed: 0

    readonly property var glow: cfg.glow || {}
    readonly property var peakCfg: cfg.peaks || {}
    readonly property var hueCfg: cfg.hue || {}
    readonly property var blockCfg: cfg.blocks || {}
    readonly property var waveCfg: cfg.wave || {}
    readonly property var circleCfg: cfg.circle || {}
    readonly property string style: cfg.style || "bars"
    readonly property string colorMode: cfg.colorMode || "gradient"
    readonly property bool perBar: (colorMode === "perBar" || colorMode === "hue") && style !== "wave"

    function drawStatic() {
        shown = targets;
        peaks = targets;
        canvas.requestPaint();
    }
    // targets may be set before live is, so check again once both are known
    onLiveChanged: if (!live) drawStatic()
    Component.onCompleted: if (!live) drawStatic()

    onTargetsChanged: {
        if (!live) {
            drawStatic();
            return;
        }
        if (targets.some(v => v > 15)) {
            silent = false;
            silenceTimer.restart();
        }
    }

    Timer {
        id: silenceTimer
        interval: root.cfg.silenceDelay * 1000
        onTriggered: root.silent = true
    }

    opacity: live && cfg.hideWhenSilent && silent ? 0 : (cfg.alpha || 0)
    Behavior on opacity {
        NumberAnimation { duration: 600; easing.type: Easing.InOutQuad }
    }

    FrameAnimation {
        running: root.live && root.visible && root.opacity > 0
        onTriggered: {
            const sec = Math.min(frameTime, 0.1);
            const dt = sec * 60;
            root.elapsed += sec;
            const up = 1 - Math.pow(1 - root.cfg.attack, dt);
            const down = 1 - Math.pow(1 - root.cfg.decay, dt);
            const t = root.targets;
            const n = t.length;
            const s = root.shown.length === n ? root.shown : t.map(() => 0);
            const pk = root.peaks.length === n ? root.peaks : t.map(() => 0);
            const hold = root.peakHold.length === n ? root.peakHold : t.map(() => 0);
            const holdTime = root.peakCfg.hold;
            const fall = root.peakCfg.fallSpeed * sec;
            const out = new Array(n);
            for (let i = 0; i < n; i++) {
                out[i] = s[i] + (t[i] - s[i]) * (t[i] > s[i] ? up : down);
                if (out[i] >= pk[i]) {
                    pk[i] = out[i];
                    hold[i] = holdTime;
                } else if (hold[i] > 0) {
                    hold[i] -= sec;
                } else {
                    pk[i] = Math.max(out[i], pk[i] - fall);
                }
            }
            root.shown = out;
            root.peaks = pk;
            root.peakHold = hold;
            canvas.requestPaint();
        }
    }

    // ---- colours --------------------------------------------------------
    function hsl(h, s, l) {
        return Qt.hsla((((h % 360) + 360) % 360) / 360, s, l, 1).toString();
    }

    // Base colour list for the current mode (n = bars on screen).
    function paletteFor(n) {
        let list;
        switch (colorMode) {
        case "hue": {
            const a = hueCfg.start, b = hueCfg.end;
            const shift = (hueCfg.speed) * elapsed;
            const sat = hueCfg.saturation, lig = hueCfg.lightness;
            const steps = Math.max(2, n);
            list = [];
            for (let i = 0; i < steps; i++)
                list.push(hsl(a + (b - a) * i / (steps - 1) + shift, sat, lig));
            break;
        }
        case "cover":
            list = coverColors.length ? coverColors.slice(0, cfg.coverColorCount) : (cfg.colors || ["#ffffff"]);
            break;
        case "accent":
            list = [Qt.darker(accentColor, 1.3).toString(), accentColor.toString(), Qt.lighter(accentColor, 1.4).toString()];
            break;
        default:
            list = cfg.colors || ["#ffffff"];
        }
        return cfg.reverseColors ? list.slice().reverse() : list;
    }

    function addStops(g, list) {
        if (list.length === 1) {
            g.addColorStop(0, list[0]);
            g.addColorStop(1, list[0]);
            return;
        }
        if (cfg.smoothGradient) {
            list.forEach((c, i) => g.addColorStop(i / (list.length - 1), c));
        } else {
            // hard bands
            list.forEach((c, i) => {
                g.addColorStop(i / list.length, c);
                g.addColorStop(Math.min(1, (i + 1) / list.length - 0.0001), c);
            });
        }
    }

    // Shared fill for the non per-bar modes.
    function makeFill(ctx, list, geo) {
        if (list.length === 1)
            return list[0];
        const dir = cfg.gradient || "vertical";
        let g;
        if (geo.circle) {
            g = dir === "horizontal"
                ? ctx.createConicalGradient(geo.cx, geo.cy, Math.PI / 2)
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
        addStops(g, list);
        return g;
    }

    // ---- drawing --------------------------------------------------------
    function displayed(arr) {
        let v = cfg.reverse ? arr.slice().reverse() : arr;
        if (cfg.symmetric)
            v = v.slice().reverse().concat(v);
        return v;
    }

    function norm(x) {
        return Math.max(0, Math.min(1, x / 1000 * (cfg.heightScale)));
    }

    function linearX(n) {
        const gap = cfg.gap;
        const fixed = cfg.width;
        const bw = fixed > 0 ? fixed : Math.max(1, (width - gap * (n - 1)) / n);
        const total = n * bw + (n - 1) * gap;
        return { bw: bw, gap: gap, offset: Math.max(0, (width - total) / 2) };
    }

    function spanY(h) {
        if (cfg.align === "center")
            return (height - h) / 2;
        if (cfg.align === "top")
            return 0;
        return height - h;
    }

    function drawBars(ctx, v, colors, fill) {
        const n = v.length;
        const L = linearX(n);
        const r = cfg.radius;
        const minH = cfg.minHeight;
        for (let i = 0; i < n; i++) {
            const h = Math.max(minH, norm(v[i]) * height);
            const x = L.offset + i * (L.bw + L.gap);
            const y = spanY(h);
            ctx.fillStyle = perBar ? colors[i % colors.length] : fill;
            const rr = Math.min(r, L.bw / 2, h / 2);
            if (rr > 0) {
                ctx.beginPath();
                ctx.roundedRect(x, y, L.bw, h, rr, rr);
                ctx.fill();
            } else {
                ctx.fillRect(x, y, L.bw, h);
            }
        }
    }

    function drawBlocks(ctx, v, colors, fill) {
        const n = v.length;
        const L = linearX(n);
        const bh = blockCfg.height;
        const bg = blockCfg.gap;
        let rows = Math.max(1, Math.floor((height + bg) / (bh + bg)));
        const center = cfg.align === "center";
        if (center && rows % 2 === 0)
            rows--;
        const inactive = blockCfg.inactive || {};
        const r = Math.min(cfg.radius, bh / 2, L.bw / 2);
        const rect = (x, y) => {
            if (r > 0) {
                ctx.beginPath();
                ctx.roundedRect(x, y, L.bw, bh, r, r);
                ctx.fill();
            } else {
                ctx.fillRect(x, y, L.bw, bh);
            }
        };
        for (let i = 0; i < n; i++) {
            const x = L.offset + i * (L.bw + L.gap);
            const active = Math.round(norm(v[i]) * rows);
            const color = perBar ? colors[i % colors.length] : fill;
            for (let row = 0; row < rows; row++) {
                let on, y;
                if (center) {
                    const k = row - Math.floor(rows / 2);
                    on = Math.abs(k) < Math.ceil(active / 2);
                    y = height / 2 + k * (bh + bg) - bh / 2;
                } else if (cfg.align === "top") {
                    on = row < active;
                    y = row * (bh + bg);
                } else {
                    on = row < active;
                    y = height - (row + 1) * bh - row * bg;
                }
                if (on) {
                    ctx.fillStyle = color;
                    rect(x, y);
                } else if (inactive.show) {
                    ctx.fillStyle = inactive.color;
                    rect(x, y);
                }
            }
        }
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

    function drawWave(ctx, v, stroke, area) {
        const n = v.length;
        if (n < 2)
            return;
        const lw = waveCfg.lineWidth;
        const mode = waveCfg.mode || "curve";
        const pts = [], low = [];
        for (let i = 0; i < n; i++) {
            const x = i * width / (n - 1);
            const a = norm(v[i]);
            if (cfg.align === "center") {
                pts.push({ x: x, y: height / 2 - a * (height / 2 - lw) });
                low.push({ x: x, y: height / 2 + a * (height / 2 - lw) });
            } else if (cfg.align === "top") {
                pts.push({ x: x, y: lw / 2 + a * (height - lw) });
            } else {
                pts.push({ x: x, y: height - lw / 2 - a * (height - lw) });
            }
        }
        if (area) {
            ctx.globalAlpha = waveCfg.fillOpacity;
            ctx.beginPath();
            trace(ctx, pts, mode, true);
            if (cfg.align === "center") {
                trace(ctx, low.slice().reverse(), mode, false);
            } else {
                const base = cfg.align === "top" ? 0 : height;
                ctx.lineTo(width, base);
                ctx.lineTo(0, base);
            }
            ctx.closePath();
            ctx.fillStyle = area;
            ctx.fill();
            ctx.globalAlpha = 1;
        }
        if (lw > 0) {
            ctx.lineWidth = lw;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.strokeStyle = stroke;
            ctx.beginPath();
            trace(ctx, pts, mode, true);
            ctx.stroke();
            if (cfg.align === "center") {
                ctx.beginPath();
                trace(ctx, low, mode, true);
                ctx.stroke();
            }
        }
    }

    function circleGeo() {
        const R = Math.min(width, height) / 2;
        const inner = R * (circleCfg.size);
        return { circle: true, cx: width / 2, cy: height / 2, inner: inner, outer: R, len: R - inner };
    }

    function drawCircle(ctx, v, colors, fill, geo) {
        const n = v.length;
        const step = 2 * Math.PI / n;
        const gap = (cfg.gap) / Math.max(1, geo.inner);
        const rot = (circleCfg.rotation) * Math.PI / 180 - Math.PI / 2;
        if (style === "wave") {
            const lw = waveCfg.lineWidth;
            const pts = [];
            for (let i = 0; i <= n; i++) {
                const k = i % n;
                const a = rot + k * step;
                const r = geo.inner + norm(v[k]) * (geo.len - lw);
                pts.push({ x: geo.cx + Math.cos(a) * r, y: geo.cy + Math.sin(a) * r });
            }
            ctx.beginPath();
            trace(ctx, pts, waveCfg.mode || "curve", true);
            ctx.closePath();
            if (waveCfg.fill) {
                ctx.fillStyle = fill;
                ctx.globalAlpha = waveCfg.fillOpacity;
                ctx.fill();
                ctx.globalAlpha = 1;
            }
            if (lw > 0) {
                ctx.lineWidth = lw;
                ctx.strokeStyle = fill;
                ctx.stroke();
            }
            return;
        }
        const bh = blockCfg.height, bg = blockCfg.gap;
        const inactive = blockCfg.inactive || {};
        const sector = (r1, r2, a1, a2) => {
            ctx.beginPath();
            ctx.arc(geo.cx, geo.cy, r1, a1, a2, false);
            ctx.arc(geo.cx, geo.cy, r2, a2, a1, true);
            ctx.closePath();
            ctx.fill();
        };
        const half = Math.max(0.001, (step - gap) / 2);
        for (let i = 0; i < n; i++) {
            const a = rot + (i + 0.5) * step;
            const len = Math.max(cfg.minHeight, norm(v[i]) * geo.len);
            const color = perBar ? colors[i % colors.length] : fill;
            if (style === "blocks") {
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
                    sector(r1, r1 + bh, a - half, a + half);
                }
            } else {
                ctx.fillStyle = color;
                sector(geo.inner, geo.inner + len, a - half, a + half);
            }
        }
    }

    function drawPeaks(ctx, p, colors, fill) {
        const n = p.length;
        const L = linearX(n);
        const ph = peakCfg.height;
        const own = peakCfg.color || "";
        ctx.fillStyle = own || fill;
        for (let i = 0; i < n; i++) {
            const h = norm(p[i]) * height;
            if (h < 1)
                continue;
            if (perBar && !own)
                ctx.fillStyle = colors[i % colors.length];
            const x = L.offset + i * (L.bw + L.gap);
            if (cfg.align === "center") {
                ctx.fillRect(x, (height - h) / 2 - ph - 1, L.bw, ph);
                ctx.fillRect(x, (height + h) / 2 + 1, L.bw, ph);
            } else if (cfg.align === "top") {
                ctx.fillRect(x, h + 1, L.bw, ph);
            } else {
                ctx.fillRect(x, height - h - ph - 1, L.bw, ph);
            }
        }
    }

    onCfgChanged: if (!live) canvas.requestPaint()
    onWidthChanged: if (!live) canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        // a paint requested before the canvas is ready is dropped
        onAvailableChanged: if (available) requestPaint()
        layer.enabled: root.glow.enabled === true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: (root.glow.color && root.glow.color !== "auto") ? root.glow.color : root.paletteFor(1)[0]
            shadowBlur: root.glow.blur
            shadowOpacity: root.glow.strength
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            shadowScale: 1.02
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const v = root.displayed(root.shown);
            const n = v.length;
            if (!n || width <= 0 || height <= 0)
                return;
            const circle = root.circleCfg.enabled;
            const geo = circle ? root.circleGeo() : { circle: false };
            const colors = root.paletteFor(n);
            const fill = root.makeFill(ctx, colors, geo);

            if (circle) {
                root.drawCircle(ctx, v, colors, fill, geo);
            } else if (root.style === "wave") {
                let area = null;
                if (root.waveCfg.fill) {
                    const fc = root.waveCfg.fillColors;
                    area = fc && fc.length ? root.makeFill(ctx, fc, geo) : fill;
                }
                root.drawWave(ctx, v, fill, area);
            } else {
                if (root.style === "blocks")
                    root.drawBlocks(ctx, v, colors, fill);
                else
                    root.drawBars(ctx, v, colors, fill);
                if (root.peakCfg.enabled)
                    root.drawPeaks(ctx, root.displayed(root.peaks), colors, fill);
            }
        }
    }
}
