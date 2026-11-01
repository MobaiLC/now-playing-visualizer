// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// What Helper.qml reads from outside: the NPV_PORT variable and the helper's
// messages. Whatever listens on the port may not be our helper (any local
// user can open one first), so nothing it sends is trusted as it is.
.pragma library

var DEFAULT_PORT = 47811;
// same rule as parse_port() in helper.py, so both sides pick the same port
var MIN_PORT = 1024;
var MAX_PORT = 65535;
// the helper protocol this widget needs (PROTOCOL in helper.py); helpers
// before it don't send one, which counts as 1
var PROTOCOL = 2;

// true when a helper's schema message says it is older than this widget
function outdated(message) {
    const p = message ? message.protocol : undefined;
    return !(typeof p === "number" && p >= PROTOCOL);
}

// bars.count tops out at 128; stereo doesn't add any
var MAX_BARS = 256;

// NPV_PORT as a port number, or DEFAULT_PORT when it is empty or not a plain
// number in MIN_PORT..MAX_PORT.
function parsePort(text) {
    if (typeof text !== "string" || !/^[0-9]{1,5}$/.test(text))
        return DEFAULT_PORT;
    const port = Number(text);
    return port >= MIN_PORT && port <= MAX_PORT ? port : DEFAULT_PORT;
}

function helperUrl(port) {
    return "ws://127.0.0.1:" + port;
}

// A "B12;340;…" frame as numbers clamped to 0..1000 (anything else counts as
// 0), at most MAX_BARS of them: the canvas never gets NaN or a huge array.
function parseBars(frame) {
    const parts = frame.slice(1).split(";", MAX_BARS);
    const out = new Array(parts.length);
    for (let i = 0; i < parts.length; i++) {
        const v = Number(parts[i]);
        out[i] = v > 0 ? Math.min(v, 1000) : 0;
    }
    return out;
}

// A JSON message as an object with a string "type", or null when it is not
// valid JSON or not shaped like one of our messages.
function parseMessage(text) {
    let m;
    try {
        m = JSON.parse(text);
    } catch (e) {
        return null;
    }
    return m !== null && typeof m === "object" && !Array.isArray(m) && typeof m.type === "string" ? m : null;
}
