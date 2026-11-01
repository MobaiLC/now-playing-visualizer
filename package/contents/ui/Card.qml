// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "theme.js" as Theme
import "players.js" as Players

// The now-playing card: cover, song info, progress, controls and bars. Pure
// view: everything comes in through properties and every user action goes
// out through action(), so the widget, the live preview and the preset
// thumbnails all draw exactly the same thing.
Rectangle {
    id: card

    // full config as sent by the helper (Qt colour format)
    property var cfg: ({})
    // { track, artist, album, artUrl, identity, can* flags } or null for "Nothing playing"
    property var media: null
    property bool showProgress: false
    property real positionMs: 0
    property real lengthMs: 0
    property var barValues: []
    // false: draw barValues once instead of animating (thumbnails)
    property bool liveBars: true
    // false: no hover controls, seeking or clicks (thumbnails)
    property bool interactive: true

    // "playPause" | "next" | "previous" | "raise" | "seek" (µs) | "volume" (delta)
    signal action(string name, var value)

    readonly property var panelCfg: cfg.panel || {}
    readonly property var barsCfg: cfg.bars || {}
    readonly property var controlsCfg: cfg.controls || {}
    readonly property string fontFamily: (cfg.font && cfg.font.family) || Kirigami.Theme.defaultFont.family

    // ---- layout ---------------------------------------------------------------
    // Sizes are computed from the card itself, not from its children, so the
    // layout never feeds back into itself.
    readonly property real pad: panelCfg.padding
    readonly property real gap: panelCfg.spacing
    readonly property real innerW: Math.max(0, width - 2 * pad)
    readonly property real innerH: Math.max(0, height - 2 * pad)
    readonly property string mode: {
        const m = (cfg.layout && cfg.layout.mode) || "auto";
        if (m !== "auto")
            return m;
        if (height < Kirigami.Units.gridUnit * 4.5)
            return "compact";
        return width / Math.max(1, height) < 1.3 ? "vertical" : "horizontal";
    }
    readonly property bool barsShown: barsCfg.show === true
    readonly property real barsShare: barsShown ? barsCfg.areaRatio : 0
    readonly property bool headerShown: cfg.header.show && mode !== "compact" && media !== null
    readonly property real headerH: headerShown ? cfg.header.size * 1.4 + 8 : 0
    // the song block: everything except the bars
    readonly property real infoW: mode === "vertical" ? innerW : (innerW - (barsShown ? gap : 0)) * (1 - barsShare)
    readonly property real infoH: mode === "vertical" ? (innerH - (barsShown ? gap : 0)) * (1 - barsShare) - headerH : innerH - headerH
    readonly property real coverSide: !cfg.cover.show ? 0
        : mode === "compact" ? innerH
        : Math.max(0, Math.min(infoH, infoW * 0.4))

    // ---- helpers --------------------------------------------------------------
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

    function can(flag) {
        return interactive && !!media && media[flag] === true;
    }

    readonly property bool controlsVisible: {
        const m = controlsCfg.show || "hover";
        if (!interactive || !media || !media.canControl || m === "never")
            return false;
        return m === "always" || hover.hovered;
    }

    // ---- colours -------------------------------------------------------------------
    // With "panel.colorSource": "cover" the card takes its colours from the
    // cover (theme.js keeps them readable); with no cover, or before its
    // colours are known, it uses the configured ones. The previous cover's
    // colours stay while the next one loads, so songs fade into each other.
    readonly property string artUrl: media?.artUrl ?? ""
    readonly property var theme: panelCfg.colorSource === "cover" && artUrl !== "" && cover.status !== Image.Error
        ? Theme.fromCover(coverPalette.colors, coverPalette.dominant, Qt.color(panelCfg.color).a,
                          backdropShown ? { average: coverPalette.average, dim: panelCfg.coverDim } : null)
        : null
    property color bgColor: theme ? theme.background : panelCfg.color
    property color borderColor: theme ? theme.border : panelCfg.borderColor
    property color headerColor: theme ? theme.header : cfg.header.color
    property color titleColor: theme ? theme.title : cfg.title.color
    property color subtitleColor: theme ? theme.subtitle : cfg.subtitle.color
    property color timeColor: theme ? theme.time : cfg.progress.timeColor
    property color progressColor: theme ? theme.progress : cfg.progress.color
    property color trackColor: theme ? theme.track : cfg.progress.trackColor
    component Fade: ColorAnimation { duration: 600; easing.type: Easing.InOutQuad }
    Behavior on bgColor { enabled: card.interactive; Fade {} }
    Behavior on borderColor { enabled: card.interactive; Fade {} }
    Behavior on headerColor { enabled: card.interactive; Fade {} }
    Behavior on titleColor { enabled: card.interactive; Fade {} }
    Behavior on subtitleColor { enabled: card.interactive; Fade {} }
    Behavior on timeColor { enabled: card.interactive; Fade {} }
    Behavior on progressColor { enabled: card.interactive; Fade {} }
    Behavior on trackColor { enabled: card.interactive; Fade {} }

    color: backdrop.visible ? "transparent" : fade(bgColor, panelCfg.opacity)
    radius: panelCfg.radius
    border.width: panelCfg.borderWidth
    border.color: fade(borderColor, panelCfg.opacity)

    HoverHandler {
        id: hover
        enabled: card.interactive
    }
    WheelHandler {
        enabled: card.interactive && card.controlsCfg.scrollVolume === true
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => card.action("volume", event.angleDelta.y > 0 ? 0.05 : -0.05)
    }

    // ---- reusable pieces ----------------------------------------------------------
    // Text that scrolls when it doesn't fit (on hover or always), elided otherwise.
    component MarqueeText: Item {
        id: mq
        property alias text: label.text
        property alias color: label.color
        property alias font: label.font
        readonly property real overflow: Math.max(0, label.implicitWidth - width)
        readonly property bool scrolling: {
            const m = card.cfg.title.marquee || "hover";
            return overflow > 0 && card.interactive && (m === "always" || (m === "hover" && hover.hovered));
        }
        implicitHeight: label.implicitHeight
        clip: true
        Text {
            id: label
            width: mq.scrolling ? implicitWidth : mq.width
            // titles come from any MPRIS player: never render them as HTML
            textFormat: Text.PlainText
            elide: mq.scrolling ? Text.ElideNone : Text.ElideRight
            font.family: card.fontFamily
        }
        SequentialAnimation {
            running: mq.scrolling
            loops: Animation.Infinite
            onStopped: label.x = 0
            PauseAnimation { duration: 1200 }
            NumberAnimation { target: label; property: "x"; to: -mq.overflow; duration: Math.max(800, mq.overflow * 28); easing.type: Easing.InOutSine }
            PauseAnimation { duration: 1200 }
            NumberAnimation { target: label; property: "x"; to: 0; duration: Math.max(800, mq.overflow * 28); easing.type: Easing.InOutSine }
        }
    }

    component ControlButton: Kirigami.Icon {
        id: btn
        property string name
        property bool allowed: true
        // sent with the action (shuffle: the new state, loop: the next mode)
        property var value: null
        // off toggles (shuffle, repeat) are drawn dimmed
        property bool toggledOn: true
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: implicitWidth
        color: "white"
        isMask: true
        opacity: !allowed ? 0.3 : !toggledOn ? (tapHover.hovered ? 0.7 : 0.45) : (tapHover.hovered ? 1 : 0.85)
        HoverHandler {
            id: tapHover
            enabled: btn.allowed
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: btn.allowed
            onTapped: card.action(btn.name, btn.value)
        }
    }

    component Controls: Row {
        id: ctl
        property real size: Kirigami.Units.iconSizes.small
        spacing: size * 0.35
        ControlButton {
            name: "previous"
            source: "media-skip-backward"
            allowed: card.can("canGoPrevious")
            width: ctl.size; height: ctl.size
        }
        ControlButton {
            name: "playPause"
            source: card.media && card.media.playing ? "media-playback-pause" : "media-playback-start"
            allowed: card.can("canPlayPause")
            width: ctl.size * 1.25; height: ctl.size * 1.25
            anchors.verticalCenter: parent.verticalCenter
        }
        ControlButton {
            name: "next"
            source: "media-skip-forward"
            allowed: card.can("canGoNext")
            width: ctl.size; height: ctl.size
        }
    }

    // Shuffle and repeat, each only when the player has it (null = it
    // doesn't: Firefox, Chromium...) and can be controlled. undefined (an
    // older helper that doesn't send them) hides them too.
    readonly property bool extrasShown: interactive && !!media && media.canControl === true
        && controlsCfg.shuffleRepeat !== false && (media.shuffle != null || media.loop != null)
    component ExtraControls: Row {
        id: ex
        property real size: Kirigami.Units.iconSizes.small
        spacing: size * 0.6
        visible: card.extrasShown
        ControlButton {
            name: "shuffle"
            source: "media-playlist-shuffle"
            visible: card.media?.shuffle != null
            toggledOn: card.media?.shuffle === true
            value: card.media?.shuffle !== true
            width: ex.size; height: ex.size
        }
        ControlButton {
            name: "loop"
            source: card.media?.loop === "Track" ? "media-playlist-repeat-song" : "media-playlist-repeat"
            visible: card.media?.loop != null
            toggledOn: (card.media?.loop ?? "None") !== "None"
            value: Players.nextLoop(card.media?.loop)
            width: ex.size; height: ex.size
        }
    }

    // ---- blurred cover behind everything ("panel.coverBackground") ---------------
    // Off in the preset thumbnails, which never show a cover. A 64 px source is
    // plenty for a blur and keeps it cheap; it is only redrawn when the cover
    // or the size changes.
    readonly property bool backdropShown: interactive && panelCfg.coverBackground === true && artUrl !== ""
    Item {
        id: backdrop
        anchors.fill: parent
        anchors.margins: card.border.width
        visible: card.backdropShown && backdropImage.status === Image.Ready
        opacity: card.panelCfg.opacity
        Image {
            id: backdropImage
            anchors.fill: parent
            source: card.backdropShown ? card.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 64
            sourceSize.height: 64
            visible: false
        }
        Rectangle {
            id: backdropMask
            anchors.fill: parent
            radius: Math.max(0, card.radius - card.border.width)
            visible: false
            layer.enabled: true
            layer.smooth: true
        }
        MultiEffect {
            anchors.fill: parent
            source: backdropImage
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: card.panelCfg.coverBlur
            maskEnabled: true
            maskSource: backdropMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        // the card's own background colour over it, so the text stays readable
        Rectangle {
            anchors.fill: parent
            radius: backdropMask.radius
            color: card.fade(card.bgColor, card.panelCfg.coverDim)
        }
    }

    // ---- content ------------------------------------------------------------------
    GridLayout {
        anchors.fill: parent
        anchors.margins: card.pad
        columnSpacing: card.gap
        rowSpacing: card.gap
        flow: card.mode === "vertical" ? GridLayout.TopToBottom : GridLayout.LeftToRight
        layoutDirection: card.barsCfg.side === "left" && card.mode !== "vertical" ? Qt.RightToLeft : Qt.LeftToRight
        columns: card.mode === "vertical" ? 1 : 2
        rows: card.mode === "vertical" ? 2 : 1

        // song block
        ColumnLayout {
            Layout.preferredWidth: card.infoW
            Layout.maximumWidth: card.infoW
            Layout.preferredHeight: card.infoH + card.headerH
            Layout.fillHeight: card.mode !== "vertical"
            spacing: 8

            Text {
                Layout.fillWidth: true
                visible: card.headerShown
                text: card.fillTemplate(card.cfg.header.text || i18n("Listening to {title}"))
                textFormat: Text.PlainText
                color: card.headerColor
                font.family: card.fontFamily
                font.pixelSize: card.cfg.header.size
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: card.mode === "compact" ? 10 : 12

                Item {
                    id: coverBox
                    visible: card.coverSide > 0
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: card.coverSide
                    Layout.preferredHeight: card.coverSide

                    Image {
                        id: cover
                        anchors.fill: parent
                        source: card.artUrl
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

                    // controls over the cover, shown on hover
                    Rectangle {
                        anchors.fill: parent
                        radius: coverMask.radius
                        color: "#8c000000"
                        opacity: card.controlsVisible && card.coverSide >= Kirigami.Units.gridUnit * 3 ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }
                        // shuffle and repeat go on a smaller second row: five
                        // buttons don't fit across a small cover
                        Column {
                            anchors.centerIn: parent
                            spacing: overlayControls.size * 0.3
                            Controls {
                                id: overlayControls
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: Math.max(Kirigami.Units.iconSizes.small, card.coverSide * 0.2)
                            }
                            ExtraControls {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: overlayControls.size * 0.75
                            }
                        }
                    }
                    HoverHandler {
                        enabled: card.can("canRaise")
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        // a click on the cover brings the player's window forward,
                        // unless it landed on one of the controls above it
                        enabled: card.can("canRaise") && !card.controlsVisible
                        onTapped: card.action("raise", null)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2

                    Item { Layout.fillHeight: true }
                    MarqueeText {
                        Layout.fillWidth: true
                        text: card.media ? card.media.track : i18n("Nothing playing")
                        color: card.titleColor
                        font.pixelSize: card.cfg.title.size
                        font.bold: card.cfg.title.bold
                    }
                    MarqueeText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.media?.artist ?? ""
                        color: card.subtitleColor
                        font.pixelSize: card.cfg.subtitle.size
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.cfg.subtitle.showAlbum && text !== "" && card.mode !== "compact"
                        text: card.media?.album ?? ""
                        textFormat: Text.PlainText
                        color: card.subtitleColor
                        font.family: card.fontFamily
                        font.pixelSize: card.cfg.subtitle.size
                        elide: Text.ElideRight
                    }
                    // controls in the text column when the cover is hidden or too small
                    Row {
                        visible: card.controlsVisible && card.mode !== "compact" && card.coverSide < Kirigami.Units.gridUnit * 3
                        spacing: Kirigami.Units.iconSizes.small * 0.8
                        Controls {
                            size: Kirigami.Units.iconSizes.small
                        }
                        ExtraControls {
                            anchors.verticalCenter: parent.verticalCenter
                            size: Kirigami.Units.iconSizes.small
                        }
                    }
                    Item { Layout.preferredHeight: 4 }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: card.cfg.progress.show && card.showProgress && card.mode !== "compact"
                        spacing: 8

                        Text {
                            visible: card.cfg.progress.showTimes
                            text: card.fmt(seek.pressed ? seek.previewMs : card.positionMs)
                            color: card.timeColor
                            font.family: card.fontFamily
                            font.pixelSize: card.cfg.progress.timeSize
                            font.features: { "tnum": 1 }
                        }
                        // the bar; click or drag it to seek when the player allows
                        Item {
                            id: progress
                            Layout.fillWidth: true
                            implicitHeight: Math.max(card.cfg.progress.height, 12)
                            readonly property real shownMs: seek.pressed ? seek.previewMs : card.positionMs
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: card.cfg.progress.height
                                radius: height / 2
                                color: card.trackColor
                                Rectangle {
                                    width: card.lengthMs > 0 ? parent.width * progress.shownMs / card.lengthMs : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: card.progressColor
                                }
                            }
                            Rectangle {
                                // knob, only while it can be used
                                visible: seek.enabled && (seek.containsMouse || seek.pressed)
                                width: Math.max(8, card.cfg.progress.height * 3)
                                height: width
                                radius: width / 2
                                color: card.progressColor
                                anchors.verticalCenter: parent.verticalCenter
                                x: (card.lengthMs > 0 ? parent.width * progress.shownMs / card.lengthMs : 0) - width / 2
                            }
                            MouseArea {
                                id: seek
                                anchors.fill: parent
                                enabled: card.can("canSeek") && card.lengthMs > 0
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                property real previewMs: 0
                                function msAt(x) {
                                    return Math.max(0, Math.min(1, x / width)) * card.lengthMs;
                                }
                                onPressed: mouse => previewMs = msAt(mouse.x)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        previewMs = msAt(mouse.x);
                                }
                                onReleased: mouse => card.action("seek", Math.round(msAt(mouse.x) * 1000))
                            }
                        }
                        Text {
                            visible: card.cfg.progress.showTimes
                            text: card.fmt(card.lengthMs)
                            color: card.timeColor
                            font.family: card.fontFamily
                            font.pixelSize: card.cfg.progress.timeSize
                            font.features: { "tnum": 1 }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // compact cards have no room under the title: controls sit beside it
                Row {
                    visible: card.controlsVisible && card.mode === "compact"
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Kirigami.Units.iconSizes.small * 0.8
                    Controls {
                        size: Kirigami.Units.iconSizes.small
                    }
                    ExtraControls {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Kirigami.Units.iconSizes.small
                    }
                }
            }
        }

        Bars {
            visible: card.barsShown
            cfg: card.barsCfg
            targets: card.barValues
            live: card.liveBars
            coverColors: coverPalette.colors
            accentColor: Kirigami.Theme.highlightColor
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
