// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Which player the widget shows, and the player menu. The same rules as
// pick_player() in helper.py, so the D-Bus fallback and the audio
// ("Follow the player") agree with what the widget shows.
.pragma library

// MPRIS LoopStatus values, in the order the repeat button cycles through them
var LOOP_STATUSES = ["None", "Playlist", "Track"];

function lower(s) {
    return (s || "").toLowerCase();
}

// p: { identity, desktopEntry?, bus?, playing }
function isPreferred(p, preferred) {
    const id = lower(p.identity) + " " + lower(p.desktopEntry || p.bus);
    return (preferred || []).some(n => n && id.includes(lower(n)));
}

function isPinned(p, pinned) {
    return !!pinned && lower(p.identity) === lower(pinned);
}

// The player to show: the pinned one while it is open, then playing and
// preferred, then playing, then preferred, then (unless orFirst is false)
// the first. null if none. MprisSource.qml passes orFirst = false and falls
// back to Plasma's own current player, as it always did.
function pick(players, pinned, preferred, orFirst) {
    const tests = [
        p => isPinned(p, pinned),
        p => p.playing && isPreferred(p, preferred),
        p => p.playing,
        p => isPreferred(p, preferred)
    ];
    if (orFirst !== false)
        tests.push(p => true);
    for (const test of tests) {
        const found = players.find(test);
        if (found)
            return found;
    }
    return null;
}

// The player menu: one entry per Identity (two windows of the same browser
// are one entry), plus the pinned player when it isn't open, so it can be
// unpinned. [{ identity, open, playing }]
function menu(players, pinned) {
    const out = [];
    for (const p of players) {
        if (!p.identity || out.some(e => lower(e.identity) === lower(p.identity)))
            continue;
        out.push({ identity: p.identity, open: true, playing: !!p.playing });
    }
    if (pinned && !out.some(e => lower(e.identity) === lower(pinned)))
        out.push({ identity: pinned, open: false, playing: false });
    return out;
}

// The repeat button's next state: None -> Playlist -> Track -> None.
function nextLoop(status) {
    const i = LOOP_STATUSES.indexOf(status);
    return LOOP_STATUSES[(i + 1) % LOOP_STATUSES.length];
}
