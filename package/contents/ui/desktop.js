// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Where the quickshell desktop card goes (desktop.* in config.json).

.pragma library

// The screen named `name`, else the first one, else null (no screens yet).
function pickScreen(screens, name) {
    // a plain loop: Quickshell.screens is a QML list, not always a JS array
    for (let i = 0; i < screens.length; i++) {
        if (screens[i].name === name)
            return screens[i];
    }
    return screens.length > 0 ? screens[0] : null;
}

// Layer-shell anchors for a corner; anything unknown is bottomRight.
function anchorsFor(anchor) {
    const top = anchor === "topLeft" || anchor === "topRight";
    const left = anchor === "topLeft" || anchor === "bottomLeft";
    return { top: top, bottom: !top, left: left, right: !left };
}
