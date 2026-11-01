// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Card colours taken from the cover art, kept readable: the text is white or
// near-black, whichever contrasts more with the background (WCAG contrast
// ratio), and the accent is nudged until it stands out from it.
.pragma library

// WCAG minimums: text, and other parts of the interface (progress bar)
var TEXT_CONTRAST = 4.5;
var ACCENT_CONTRAST = 3;
// how far the background goes from the cover's main colour towards black
var DARKEN = 0.6;

function channel(x) {
    return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
}

// WCAG relative luminance, 0 (black) to 1 (white); alpha is ignored.
function luminance(c) {
    const q = Qt.color(c);
    return 0.2126 * channel(q.r) + 0.7152 * channel(q.g) + 0.0722 * channel(q.b);
}

// WCAG contrast ratio between two colours, 1 to 21.
function contrast(a, b) {
    const la = luminance(a), lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function withAlpha(c, a) {
    const q = Qt.color(c);
    return Qt.rgba(q.r, q.g, q.b, a);
}

function mix(a, b, t) {
    const p = Qt.color(a), q = Qt.color(b);
    return Qt.rgba(p.r + (q.r - p.r) * t, p.g + (q.g - p.g) * t, p.b + (q.b - p.b) * t, 1);
}

// White or near-black, whichever reads better on bg. On mid tones neither
// may reach TEXT_CONTRAST (on #777777 white gives 4.48), and pure black is
// the one that does.
function textOn(bg) {
    const white = contrast("#ffffff", bg), dark = contrast("#111111", bg);
    if (white >= dark && white >= TEXT_CONTRAST)
        return "#ffffff";
    if (dark >= TEXT_CONTRAST)
        return "#111111";
    return white > contrast("#000000", bg) ? "#ffffff" : "#000000";
}

// color itself if it stands out from bg, else the closest lighter (on a dark
// bg) or darker (on a light one) shade that does; the text colour at worst.
function accentOn(color, bg) {
    const towards = textOn(bg);
    for (let t = 0; t <= 1.0001; t += 0.1) {
        const c = mix(color, towards, t);
        if (contrast(c, bg) >= ACCENT_CONTRAST)
            return c;
    }
    return Qt.color(towards);
}

// What the text actually sits on when the blurred cover is behind the card:
// roughly the cover's average colour under bg laid over it at opacity dim.
function behindText(bg, backdrop) {
    return backdrop ? mix(backdrop.average, bg, backdrop.dim) : bg;
}

// The card's colours from a cover. vivid: the cover's colours, most vivid
// first; main: its dominant colour; alpha: the background's opacity, kept
// from the user's own background colour; backdrop: { average, dim } when the
// blurred cover is shown behind the card, else null. null when there is
// nothing to use.
function fromCover(vivid, main, alpha, backdrop) {
    if (!vivid || !vivid.length || !main)
        return null;
    const bg = mix(main, "#000000", DARKEN);
    const under = behindText(bg, backdrop || null);
    const text = textOn(under);
    const accent = accentOn(vivid[0], under);
    return {
        background: withAlpha(bg, alpha),
        border: withAlpha(accent, 0.25),
        title: Qt.color(text),
        subtitle: withAlpha(text, 0.75),
        header: withAlpha(text, 0.85),
        time: withAlpha(text, 0.85),
        progress: accent,
        track: withAlpha(accent, 0.22)
    };
}
