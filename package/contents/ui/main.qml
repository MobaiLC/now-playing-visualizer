// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
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
    readonly property var barsCfg: cfg.bars || {}
    readonly property string fontFamily: (cfg.font && cfg.font.family) || Kirigami.Theme.defaultFont.family

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

    // background-only opacity, the song info stays fully visible
    function fade(c, o) {
        const q = Qt.color(c);
        return Qt.rgba(q.r, q.g, q.b, q.a * o);
    }

    function fmt(ms) {
        const s = Math.floor(ms / 1000);
        return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
    }

    function fillTemplate(t) {
        // split/join: QML's JS engine has no String.replaceAll
        const m = shownMedia;
        return t.split("{title}").join(m?.track || "")
            .split("{artist}").join(m?.artist || "")
            .split("{album}").join(m?.album || "")
            .split("{player}").join(m?.identity || "");
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
            Rectangle {
                id: panel
                anchors.fill: parent
                color: root.fade(root.panelCfg.color, root.panelCfg.opacity)
                radius: root.panelCfg.radius
                border.width: root.panelCfg.borderWidth
                border.color: root.fade(root.panelCfg.borderColor, root.panelCfg.opacity)
                opacity: root.hasTrack && root.isPlaying ? 1
                    : !root.hasTrack && root.whenIdle === "hide" ? 0
                    : root.panelCfg.idleOpacity
                Behavior on opacity {
                    NumberAnimation { duration: 500 }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.panelCfg.padding
                    spacing: root.panelCfg.spacing
                    layoutDirection: root.barsCfg.side === "left" ? Qt.RightToLeft : Qt.LeftToRight

                    // song info
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 0
                        Layout.horizontalStretchFactor: Math.round(100 * (1 - (root.barsCfg.areaRatio)))
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            visible: root.cfg.header.show
                            text: root.fillTemplate(root.cfg.header.text || i18n("Listening to {title}"))
                            // titles come from any MPRIS player: never render them as HTML
                            textFormat: Text.PlainText
                            color: root.cfg.header.color
                            font.family: root.fontFamily
                            font.pixelSize: root.cfg.header.size
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            id: infoRow
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            Item {
                                id: coverBox
                                readonly property real side: Math.max(0, Math.min(infoRow.height, infoRow.width * 0.4))
                                visible: root.cfg.cover.show
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: side
                                Layout.preferredHeight: side

                                Image {
                                    id: cover
                                    anchors.fill: parent
                                    source: root.shownMedia?.artUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 256
                                    sourceSize.height: 256
                                    visible: false
                                }
                                Kirigami.ImageColors {
                                    id: coverPalette
                                    // most vivid colours first
                                    readonly property var colors: palette
                                        .map(p => p.color)
                                        .sort((x, y) => (y.hsvSaturation * y.hsvValue) - (x.hsvSaturation * x.hsvValue))
                                        .map(c => c.toString())
                                    source: coverFx
                                }
                                Timer {
                                    // let the masked cover render before sampling it
                                    id: paletteDelay
                                    interval: 400
                                    onTriggered: coverPalette.update()
                                }
                                Connections {
                                    target: cover
                                    function onStatusChanged() {
                                        if (cover.status === Image.Ready)
                                            paletteDelay.restart();
                                    }
                                }
                                Rectangle {
                                    id: coverMask
                                    anchors.fill: parent
                                    radius: root.cfg.cover.radius
                                    visible: false
                                    layer.enabled: true
                                    layer.smooth: true
                                }
                                MultiEffect {
                                    id: coverFx
                                    anchors.fill: parent
                                    source: cover
                                    visible: cover.status === Image.Ready
                                    maskEnabled: true
                                    maskSource: coverMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: cover.status !== Image.Ready
                                    radius: coverMask.radius
                                    color: "#ffffff14"
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.45
                                        height: width
                                        source: "media-optical-audio"
                                        opacity: 0.6
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 2

                                Item { Layout.fillHeight: true }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.shownMedia ? root.shownMedia.track : i18n("Nothing playing")
                                    textFormat: Text.PlainText
                                    color: root.cfg.title.color
                                    font.family: root.fontFamily
                                    font.pixelSize: root.cfg.title.size
                                    font.bold: root.cfg.title.bold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.shownMedia?.artist ?? ""
                                    textFormat: Text.PlainText
                                    color: root.cfg.subtitle.color
                                    font.family: root.fontFamily
                                    font.pixelSize: root.cfg.subtitle.size
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.cfg.subtitle.showAlbum && text !== ""
                                    text: root.shownMedia?.album ?? ""
                                    textFormat: Text.PlainText
                                    color: root.cfg.subtitle.color
                                    font.family: root.fontFamily
                                    font.pixelSize: root.cfg.subtitle.size
                                    elide: Text.ElideRight
                                }
                                Item { Layout.preferredHeight: 4 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.cfg.progress.show && root.hasTrack
                                    spacing: 8

                                    Text {
                                        visible: root.cfg.progress.showTimes
                                        text: root.fmt(root.positionMs)
                                        color: root.cfg.progress.timeColor
                                        font.family: root.fontFamily
                                        font.pixelSize: root.cfg.progress.timeSize
                                        font.features: { "tnum": 1 }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: root.cfg.progress.height
                                        radius: height / 2
                                        color: root.cfg.progress.trackColor
                                        Rectangle {
                                            width: root.lengthMs > 0 ? parent.width * root.positionMs / root.lengthMs : 0
                                            height: parent.height
                                            radius: parent.radius
                                            color: root.cfg.progress.color
                                        }
                                    }
                                    Text {
                                        visible: root.cfg.progress.showTimes
                                        text: root.fmt(root.lengthMs)
                                        color: root.cfg.progress.timeColor
                                        font.family: root.fontFamily
                                        font.pixelSize: root.cfg.progress.timeSize
                                        font.features: { "tnum": 1 }
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    Bars {
                        visible: root.barsCfg.show === true
                        cfg: root.barsCfg
                        targets: root.barValues
                        coverColors: coverPalette.colors
                        accentColor: Kirigami.Theme.highlightColor
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 0
                        Layout.horizontalStretchFactor: Math.round(100 * (root.barsCfg.areaRatio))
                    }
                }
            }
        }
    }
}
