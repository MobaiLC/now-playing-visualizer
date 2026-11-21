// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// Player, helper and position logic shared by the Plasma widget and the
// quickshell card. No org.kde.* imports: it must load outside Plasma too.
Item {
    id: np

    property var cfg: ({})
    property var issues: []
    readonly property var shownIssues: helper.outdatedService ? issues.concat([{ code: "helper_outdated" }]) : issues
    property var barValues: []
    // every key is present once the helper has sent the first config
    readonly property bool ready: cfg.panel !== undefined

    readonly property var panelCfg: cfg.panel || {}


    Helper {
        id: helper
        onConfigReceived: (data, issues) => {
            np.cfg = data;
            np.issues = issues;
        }
        onBarsReceived: values => np.barValues = values
        onMediaReceived: data => np.fallbackMedia = data
        onPlayersReceived: list => np.fallbackPlayers = list
    }

    // ---- media source -------------------------------------------------------
    // Plasma's MPRIS module is loaded in isolation; if it fails (or is turned
    // off with "advanced.forceDbusMedia") the helper reads MPRIS over D-Bus.
    Loader {
        id: mprisLoader
        active: !np.forceFallback
        source: "MprisSource.qml"
    }
    Binding {
        target: mprisLoader.item
        property: "preferred"
        value: np.panelCfg.preferredPlayers || []
        when: mprisLoader.item !== null
    }
    Binding {
        target: mprisLoader.item
        property: "pinned"
        value: np.pinnedPlayer
        when: mprisLoader.item !== null
    }

    property string pinnedPlayer: ""
    property var fallbackPlayers: []
    readonly property var openPlayers: useFallback ? fallbackPlayers : (mprisLoader.item ? mprisLoader.item.playerList : [])

    function sendPin() {
        helper.send({ type: "pinPlayer", identity: pinnedPlayer });
    }
    onPinnedPlayerChanged: sendPin()

    readonly property bool forceFallback: cfg.advanced?.forceDbusMedia ?? false
    readonly property bool useFallback: forceFallback || mprisLoader.status === Loader.Error
    property var fallbackMedia: null

    function requestFallback() {
        if (useFallback)
            helper.send({ type: "wantMedia" });
    }
    onUseFallbackChanged: requestFallback()
    Connections {
        target: helper
        function onConnectedChanged() {
            np.requestFallback();
            np.sendPin();
        }
    }

    readonly property var player: useFallback ? fallbackMedia : (mprisLoader.item ? mprisLoader.item.media : null)

    readonly property bool hasTrack: !!player && (player.track || "") !== ""

    // ---- idle state -----------------------------------------------------------
    // Remember the last song so the card can stay visible (dimmed) between
    // songs instead of vanishing; an invisible widget is hard to find again.
    property var lastMedia: null
    onPlayerChanged: {
        if (hasTrack)
            lastMedia = player;
        syncedPos = playerPos;
    }
    readonly property string whenIdle: panelCfg.whenIdle || "last"
    readonly property var shownMedia: hasTrack ? player : (whenIdle === "last" ? lastMedia : null)
    readonly property bool idle: !hasTrack || !isPlaying
    readonly property bool isPlaying: !!player && player.playing

    // ---- position (MPRIS gives µs; interpolate locally between syncs) -------
    // syncedPos is a plain value, not a binding: a seek sets it right away
    // (the player confirms a moment later), and assigning to a bound property
    // would cut it off from the player for good.
    readonly property real playerPos: player ? player.position : 0
    property real syncedPos: 0
    onPlayerPosChanged: syncedPos = playerPos
    property double syncedAt: Date.now()
    property double now: Date.now()
    onSyncedPosChanged: syncedAt = Date.now()
    onIsPlayingChanged: syncedAt = Date.now()
    readonly property real lengthMs: player ? player.length / 1000 : 0
    readonly property real positionMs: {
        let p = syncedPos / 1000;
        if (isPlaying)
            p += (now - syncedAt) * (player.rate || 1);
        return Math.max(0, lengthMs > 0 ? Math.min(p, lengthMs) : p);
    }

    Timer {
        interval: 250
        running: np.isPlaying
        repeat: true
        onTriggered: np.now = Date.now()
    }
    Timer {
        interval: 2000
        running: np.isPlaying
        repeat: true
        onTriggered: {
            if (!np.useFallback && mprisLoader.item)
                mprisLoader.item.sync();
        }
    }

    function mediaAction(name, value) {
        // volume always goes through the helper: many players (Liner, other
        // Chromium/Electron apps) have no MPRIS volume, so it falls back to
        // the app's own PipeWire stream
        if (useFallback || name === "volume")
            helper.send({ type: "mediaAction", action: name, value: value, identity: player ? player.identity : "" });
        else if (mprisLoader.item)
            mprisLoader.item.act(name, value);
        // show a seek right away instead of waiting for the next sync
        if (name === "seek") {
            syncedPos = value;
            syncedAt = Date.now();
        }
    }

    function send(obj) {
        helper.send(obj);
    }
}
