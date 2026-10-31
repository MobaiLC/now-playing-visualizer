// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var cfg: ({})
    property var issues: []
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
    }
    readonly property string whenIdle: panelCfg.whenIdle || "last"
    readonly property var shownMedia: hasTrack ? player : (whenIdle === "last" ? lastMedia : null)
    readonly property bool idle: !hasTrack || !isPlaying
    readonly property bool isPlaying: !!player && player.playing

    // ---- position (MPRIS gives µs; interpolate locally between syncs) -------
    property real syncedPos: player ? player.position : 0
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
        if (useFallback)
            helper.send({ type: "mediaAction", action: name, value: value });
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
            visible: root.issues.length > 0
            source: "dialog-warning"
            HoverHandler {
                id: issueHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: Plasmoid.internalAction("configure").trigger()
            }
            QQC2.ToolTip.visible: issueHover.hovered
            QQC2.ToolTip.text: root.issues.map(root.issueText).join("\n") + "\n\n" + i18n("Click to open the settings")
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
