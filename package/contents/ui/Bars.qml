// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Effects
import "renderers/common.js" as Common
import "renderers/palette.js" as Palette
import "renderers/circle.js" as Circle
import "renderers/registry.js" as Renderers

// Spectrum on a Canvas: smoothing, falling peaks, silence fade and glow live
// here; what gets drawn is decided by renderers/registry.js.
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
    // true once the bars and peaks have caught up with the targets: nothing
    // moves, so the animation stops until something changes
    property bool settled: false
    // the hue colour mode with a speed is the only thing that moves by itself
    readonly property bool animatedColors: cfg.colorMode === "hue" && !!cfg.hue && cfg.hue.speed !== 0

    readonly property var glow: cfg.glow || {}
    readonly property var peakCfg: cfg.peaks || {}
    readonly property var circleCfg: cfg.circle || {}

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
        if (settled && (targets.length !== shown.length || targets.some((v, i) => Math.abs(v - shown[i]) > 0.5)))
            settled = false;
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
        running: root.live && root.visible && root.opacity > 0 && (!root.settled || root.animatedColors)
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
            let moving = false;
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
                // values are 0..1000: half a unit is far below a pixel
                if (Math.abs(t[i] - out[i]) > 0.5 || pk[i] > out[i])
                    moving = true;
            }
            root.shown = out;
            root.peaks = pk;
            root.peakHold = hold;
            canvas.requestPaint();
            if (!moving)
                root.settled = true;
        }
    }

    // colours and drawing live in renderers/: palette.js and one file per style
    function env() {
        return { elapsed: elapsed, coverColors: coverColors, accentColor: accentColor };
    }

    // palette, fill and geometry built by the last paint; they only change
    // with the config, the size, the cover or the accent (or with time, in
    // the animated hue mode, which isn't cached)
    property var paintCache: null
    function invalidate() {
        paintCache = null;
        settled = false;
        if (!live)
            canvas.requestPaint();
    }
    onCfgChanged: invalidate()
    onWidthChanged: invalidate()
    onHeightChanged: invalidate()
    onCoverColorsChanged: invalidate()
    onAccentColorChanged: invalidate()

    // reads elapsed only in the animated hue mode, so it isn't re-evaluated every frame otherwise
    readonly property color glowColor: glow.enabled !== true ? "transparent"
        : (glow.color && glow.color !== "auto") ? glow.color
        : Palette.paletteFor(cfg, 1, { elapsed: animatedColors ? elapsed : 0, coverColors: coverColors, accentColor: accentColor })[0]

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
            shadowColor: root.glowColor
            shadowBlur: root.glow.blur
            shadowOpacity: root.glow.strength
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            shadowScale: 1.02
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const v = Common.displayed(root.shown, root.cfg);
            if (!v.length || width <= 0 || height <= 0)
                return;
            let c = root.paintCache;
            if (!c || c.n !== v.length || root.animatedColors) {
                const geo = root.circleCfg.enabled ? Circle.geometry(root.cfg, width, height) : { circle: false };
                const colors = Palette.paletteFor(root.cfg, v.length, root.env());
                c = {
                    n: v.length, geo: geo, colors: colors, perBar: Palette.isPerBar(root.cfg),
                    fill: Palette.makeFill(ctx, colors, geo, root.cfg, width, height)
                };
                if (!root.animatedColors)
                    root.paintCache = c;
            }
            const geo = c.geo;
            Renderers.draw({
                ctx: ctx, w: width, h: height, cfg: root.cfg, geo: geo,
                v: v, peaks: Common.displayed(root.peaks, root.cfg),
                colors: c.colors, perBar: c.perBar, fill: c.fill,
                makeFill: list => Palette.makeFill(ctx, list, geo, root.cfg, width, height)
            });
        }
    }
}
