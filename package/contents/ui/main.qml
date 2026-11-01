// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "players.js" as Players

PlasmoidItem {
    id: root

    property var cfg: ({})
    property var issues: []
    readonly property var shownIssues: helper.outdatedService ? issues.concat([{ code: "helper_outdated" }]) : issues
    property var barValues: []
    // every key is present once the helper has sent the first config
    readonly property bool ready: cfg.panel !== undefined

    readonly property var panelCfg: cfg.panel || {}

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    Helper {
        id: helper
        onConfigReceived: (data, issues) => {
            root.cfg = data;
            root.issues = issues;
        }
        onBarsReceived: values => root.barValues = values
        onMediaReceived: data => root.fallbackMedia = data
        onPlayersReceived: list => root.fallbackPlayers = list
    }

    // ---- media source -------------------------------------------------------
    // Plasma's MPRIS module is loaded in isolation; if it fails (or is turned
    // off with "advanced.forceDbusMedia") the helper reads MPRIS over D-Bus.
    Loader {
        id: mprisLoader
        active: !root.forceFallback
        source: "MprisSource.qml"
    }
    Binding {
        target: mprisLoader.item
        property: "preferred"
        value: root.panelCfg.preferredPlayers || []
        when: mprisLoader.item !== null
    }
    Binding {
        target: mprisLoader.item
        property: "pinned"
        value: root.pinnedPlayer
        when: mprisLoader.item !== null
    }

    // ---- player menu ----------------------------------------------------------
    // Right-click > pick a player: the widget then shows that one while it is
    // open (automatic otherwise). Saved per widget; the helper is told too,
    // so the D-Bus fallback and "Follow the player" pick the same one.
    readonly property string pinnedPlayer: Plasmoid.configuration.pinnedPlayer
    property var fallbackPlayers: []
    readonly property var openPlayers: useFallback ? fallbackPlayers : (mprisLoader.item ? mprisLoader.item.playerList : [])
    readonly property var playerMenu: Players.menu(openPlayers, pinnedPlayer)

    function pinPlayer(identity) {
        Plasmoid.configuration.pinnedPlayer = identity;
    }
    function sendPin() {
        helper.send({ type: "pinPlayer", identity: pinnedPlayer });
    }
    onPinnedPlayerChanged: sendPin()

    PlasmaCore.Action {
        id: playerHeading
        text: i18n("Show the player")
        isSeparator: true
    }
    PlasmaCore.Action {
        id: autoPlayer
        text: i18n("Automatic (the one playing)")
        checkable: true
        checked: root.pinnedPlayer === ""
        onTriggered: root.pinPlayer("")
    }
    Instantiator {
        id: playerActions
        model: root.playerMenu
        delegate: PlasmaCore.Action {
            required property var modelData
            text: modelData.open ? modelData.identity : i18n("%1 (not open)", modelData.identity)
            checkable: true
            checked: root.pinnedPlayer.toLowerCase() === modelData.identity.toLowerCase()
            // clicking the checked one (or a closed one) goes back to automatic
            onTriggered: root.pinPlayer(checked ? modelData.identity : "")
        }
    }
    Plasmoid.contextualActions: {
        const list = [playerHeading, autoPlayer];
        for (let i = 0; i < playerActions.count; i++)
            list.push(playerActions.objectAt(i));
        return list;
    }

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
            root.requestFallback();
            root.sendPin();
        }
    }

    // Apply/OK in the Design page: keep the live-edited design (see helper.py)
    readonly property string designCommit: Plasmoid.configuration.designCommit
    onDesignCommitChanged: helper.send({ type: "commitEdit" })

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
        running: root.isPlaying
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Timer {
        interval: 2000
        running: root.isPlaying
        repeat: true
        onTriggered: {
            if (!root.useFallback && mprisLoader.item)
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

    function issueText(issue) {
        switch (issue.code) {
        case "config_parse": return i18n("config.json has an error, the last valid settings are kept: %1", issue.detail);
        case "preset_missing": return i18n("The preset \"%1\" does not exist, using lookas", issue.detail);
        case "invalid_option": return i18n("Invalid value for %1, using the default", issue.detail);
        case "out_of_range": return i18n("%1 is out of range and was adjusted", issue.detail);
        case "cava_missing": return i18n("CAVA is not installed (sudo pacman -S cava)");
        case "cava_error": return i18n("CAVA failed: %1", issue.detail);
        case "sink_error": return i18n("Could not create the virtual audio output: %1", issue.detail);
        case "helper_outdated": return i18n("The helper service is from an older version. Restart it: systemctl --user restart nowplaying-viz");
        default: return issue.code + (issue.detail ? ": " + issue.detail : "");
        }
    }

    // ---- UI -----------------------------------------------------------------
    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 9
        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
        Layout.minimumHeight: Kirigami.Units.gridUnit * 4

        Loader {
            anchors.fill: parent
            active: root.ready
            sourceComponent: card
        }

        // outside the card: stays visible when the card is dimmed, hidden or
        // not built yet (e.g. config.json could not be read)
        Kirigami.Icon {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: Kirigami.Units.iconSizes.small
            height: width
            visible: root.shownIssues.length > 0
            source: "dialog-warning"
            HoverHandler {
                id: issueHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: Plasmoid.internalAction("configure").trigger()
            }
            QQC2.ToolTip.visible: issueHover.hovered
            QQC2.ToolTip.text: root.shownIssues.map(root.issueText).join("\n") + "\n\n" + i18n("Click to open the settings")
        }

        Component {
            id: card
            Card {
                anchors.fill: parent
                cfg: root.cfg
                media: root.shownMedia
                showProgress: root.hasTrack
                positionMs: root.positionMs
                lengthMs: root.lengthMs
                barValues: root.barValues
                onAction: (name, value) => root.mediaAction(name, value)
                opacity: root.hasTrack && root.isPlaying ? 1
                    : !root.hasTrack && root.whenIdle === "hide" ? 0
                    : root.panelCfg.idleOpacity
                Behavior on opacity {
                    NumberAnimation { duration: 500 }
                }
            }
        }
    }
}
