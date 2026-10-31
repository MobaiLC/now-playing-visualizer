// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami

// The now-playing card: cover, song info, progress and bars. Pure view:
// everything comes in through properties, so the widget, the live preview
// and the preset thumbnails all draw exactly the same thing.
Rectangle {
    id: card

    // full config as sent by the helper (Qt colour format)
    property var cfg: ({})
    // { track, artist, album, artUrl, identity } or null for "Nothing playing"
    property var media: null
    property bool showProgress: false
    property real positionMs: 0
    property real lengthMs: 0
    property var barValues: []
    // false: draw barValues once instead of animating (thumbnails)
    property bool liveBars: true

    readonly property var panelCfg: cfg.panel || {}
    readonly property var barsCfg: cfg.bars || {}
    readonly property string fontFamily: (cfg.font && cfg.font.family) || Kirigami.Theme.defaultFont.family

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
        const m = media;
        return t.split("{title}").join(m?.track || "")
            .split("{artist}").join(m?.artist || "")
            .split("{album}").join(m?.album || "")
            .split("{player}").join(m?.identity || "");
    }

    color: card.fade(card.panelCfg.color, card.panelCfg.opacity)
    radius: card.panelCfg.radius
    border.width: card.panelCfg.borderWidth
    border.color: card.fade(card.panelCfg.borderColor, card.panelCfg.opacity)
    RowLayout {
        anchors.fill: parent
        anchors.margins: card.panelCfg.padding
        spacing: card.panelCfg.spacing
        layoutDirection: card.barsCfg.side === "left" ? Qt.RightToLeft : Qt.LeftToRight

        // song info
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 0
            Layout.horizontalStretchFactor: Math.round(100 * (1 - (card.barsCfg.areaRatio)))
            spacing: 8

            Text {
                Layout.fillWidth: true
                visible: card.cfg.header.show
                text: card.fillTemplate(card.cfg.header.text || i18n("Listening to {title}"))
                // titles come from any MPRIS player: never render them as HTML
                textFormat: Text.PlainText
                color: card.cfg.header.color
                font.family: card.fontFamily
                font.pixelSize: card.cfg.header.size
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
                    visible: card.cfg.cover.show
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: side
                    Layout.preferredHeight: side

                    Image {
                        id: cover
                        anchors.fill: parent
                        source: card.media?.artUrl ?? ""
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
                        radius: card.cfg.cover.radius
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
                        color: "#14ffffff"  // Qt colour format: #AARRGGBB
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
                        text: card.media ? card.media.track : i18n("Nothing playing")
                        textFormat: Text.PlainText
                        color: card.cfg.title.color
                        font.family: card.fontFamily
                        font.pixelSize: card.cfg.title.size
                        font.bold: card.cfg.title.bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.media?.artist ?? ""
                        textFormat: Text.PlainText
                        color: card.cfg.subtitle.color
                        font.family: card.fontFamily
                        font.pixelSize: card.cfg.subtitle.size
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.cfg.subtitle.showAlbum && text !== ""
                        text: card.media?.album ?? ""
                        textFormat: Text.PlainText
                        color: card.cfg.subtitle.color
                        font.family: card.fontFamily
                        font.pixelSize: card.cfg.subtitle.size
                        elide: Text.ElideRight
                    }
                    Item { Layout.preferredHeight: 4 }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: card.cfg.progress.show && card.showProgress
                        spacing: 8

                        Text {
                            visible: card.cfg.progress.showTimes
                            text: card.fmt(card.positionMs)
                            color: card.cfg.progress.timeColor
                            font.family: card.fontFamily
                            font.pixelSize: card.cfg.progress.timeSize
                            font.features: { "tnum": 1 }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: card.cfg.progress.height
                            radius: height / 2
                            color: card.cfg.progress.trackColor
                            Rectangle {
                                width: card.lengthMs > 0 ? parent.width * card.positionMs / card.lengthMs : 0
                                height: parent.height
                                radius: parent.radius
                                color: card.cfg.progress.color
                            }
                        }
                        Text {
                            visible: card.cfg.progress.showTimes
                            text: card.fmt(card.lengthMs)
                            color: card.cfg.progress.timeColor
                            font.family: card.fontFamily
                            font.pixelSize: card.cfg.progress.timeSize
                            font.features: { "tnum": 1 }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }

        Bars {
            visible: card.barsCfg.show === true
            cfg: card.barsCfg
            targets: card.barValues
            live: card.liveBars
            coverColors: coverPalette.colors
            accentColor: Kirigami.Theme.highlightColor
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 0
            Layout.horizontalStretchFactor: Math.round(100 * (card.barsCfg.areaRatio))
        }
    }
}
