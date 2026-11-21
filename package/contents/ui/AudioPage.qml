// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "tr.js" as Tr

// OBS-style picker: tick the applications the visualizer should listen to,
// or let it follow whichever player the widget shows.
// Changes are written straight to config.json by the helper.
// Shared by Plasma's settings (configApps.qml) and the standalone window.
Item {
    id: page

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    property var running: []
    property var selected: []
    property bool followPlayer: false

    readonly property var rows: {
        let ids = running.map(a => a.id);
        let out = running.slice();
        for (const s of selected)
            if (!ids.includes(s))
                out.push({ id: s, name: s, icon: s, offline: true });
        return out;
    }

    function toggle(id, on) {
        let s = selected.filter(x => x !== id);
        if (on)
            s.push(id);
        selected = s;
        helper.send({ type: "setApps", apps: s });
    }

    Helper {
        id: helper
        topics: ["config", "schema"]
        onConfigReceived: (data, issues) => {
            page.selected = data.audio?.apps ?? [];
            page.followPlayer = data.audio?.followPlayer ?? false;
        }
        onAppsReceived: apps => page.running = apps
        onConnectedChanged: if (connected) send({ type: "listApps" })
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: helper.send({ type: "listApps" })
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            text: page.followPlayer
                ? Tr.tr("The visualizer listens to the player shown in the widget, whichever it is.")
                : page.selected.length === 0
                ? Tr.tr("No app selected: the visualizer listens to the whole system.")
                : Tr.tr("The visualizer only listens to the selected apps. Apps show up here while they are playing sound.")
        }

        QQC2.CheckBox {
            text: Tr.tr("Follow the player shown in the widget")
            checked: page.followPlayer
            onToggled: {
                page.followPlayer = checked;
                helper.send({ type: "setFollowPlayer", value: checked });
            }
        }

        Repeater {
            model: page.rows
            delegate: RowLayout {
                required property var modelData
                spacing: Kirigami.Units.smallSpacing
                enabled: !page.followPlayer
                QQC2.CheckBox {
                    checked: page.selected.includes(modelData.id)
                    onToggled: page.toggle(modelData.id, checked)
                }
                Kirigami.Icon {
                    source: modelData.icon || "application-x-executable"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: implicitWidth
                    fallback: "audio-volume-high"
                }
                QQC2.Label {
                    text: modelData.offline ? Tr.tr("%1 (not playing now)", modelData.name) : modelData.name
                    textFormat: Text.PlainText
                    opacity: modelData.offline ? 0.6 : 1
                }
            }
        }

        QQC2.Label {
            visible: !helper.connected
            text: Tr.tr("Connecting to the helper…")
            opacity: 0.7
        }

        RowLayout {
            QQC2.Button {
                text: Tr.tr("Refresh list")
                icon.name: "view-refresh"
                onClicked: helper.send({ type: "listApps" })
            }
            QQC2.Button {
                text: Tr.tr("Open config.json")
                icon.name: "document-edit"
                onClicked: Qt.openUrlExternally("file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation).toString().replace("file://", "") + "/nowplaying-viz/config.json")
            }
        }
    }
}
