// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ui"
import "../ui/tr.js" as Tr
import "flow.js" as Flow

// Settings for desktops without Plasma: the same Design and Audio pages as
// Plasma's dialog, run with Qt's qml tool:
//   /usr/lib/qt6/bin/qml settings.qml [-- --port N]
QQC2.ApplicationWindow {
    id: win

    title: Tr.tr("Now Playing Visualizer — Settings")
    width: Kirigami.Units.gridUnit * 40
    height: Kirigami.Units.gridUnit * 44
    visible: true

    property string flowState: "idle"
    property bool quitting: false
    readonly property bool canCommit: design.connected && !design.busy

    function run(event) {
        const r = Flow.next(flowState, event, design.unsavedChanges);
        flowState = r.state;
        for (const a of r.actions) {
            if (a === "send-commit")
                design.apply();
            else if (a === "start-timer")
                okTimeout.restart();
            else if (a === "ask")
                discardDialog.open();
            else if (a === "quit") {
                quitting = true;
                Qt.quit();
            }
            // "show-error": the footer shows it while state is "error"
        }
    }

    onClosing: close => {
        if (quitting)
            return;
        close.accepted = false;
        run("close");
    }

    Connections {
        target: design
        function onCommitted() {
            okTimeout.stop();
            win.run("ack");
        }
    }

    Timer {
        id: okTimeout
        interval: Flow.TIMEOUT_MS
        onTriggered: win.run("timeout")
    }

    MessageDialog {
        id: discardDialog
        text: Tr.tr("Discard the unapplied changes?")
        buttons: MessageDialog.Discard | MessageDialog.Cancel
        onButtonClicked: (button, role) => {
            if (button === MessageDialog.Discard)
                win.run("cancel");
        }
        onVisibleChanged: if (!visible && win.flowState === "closing") win.flowState = "idle"
    }

    header: QQC2.TabBar {
        id: tabs
        QQC2.TabButton { text: Tr.tr("Design") }
        QQC2.TabButton { text: Tr.tr("Audio") }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: !design.connected
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: Tr.tr("Can't reach the helper. Start it with: systemctl --user start nowplaying-viz")
        }
        QQC2.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            opacity: 0.7
            text: Tr.tr("If it still doesn't connect, run: nowplaying-viz doctor")
        }
    }

    // kept alive while hidden: their helper connections come up on their own
    StackLayout {
        anchors.fill: parent
        currentIndex: tabs.currentIndex
        visible: design.connected

        QQC2.Page {
            header: design.header
            QQC2.ScrollView {
                id: designScroll
                anchors.fill: parent
                DesignPage {
                    id: design
                    width: designScroll.availableWidth
                }
            }
        }
        QQC2.ScrollView {
            id: audioScroll
            AudioPage {
                width: audioScroll.availableWidth - Kirigami.Units.largeSpacing * 2
                x: Kirigami.Units.largeSpacing
                y: Kirigami.Units.largeSpacing
            }
        }
    }

    footer: QQC2.ToolBar {
        RowLayout {
            anchors.fill: parent

            QQC2.Label {
                Layout.fillWidth: true
                visible: win.flowState === "error"
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                text: Tr.tr("The helper didn't confirm the save. The changes are not applied yet.")
            }
            Item {
                Layout.fillWidth: true
                visible: win.flowState !== "error"
            }
            QQC2.Button {
                text: Tr.tr("Cancel")
                icon.name: "dialog-cancel"
                onClicked: win.run("cancel")
            }
            QQC2.Button {
                text: Tr.tr("Apply")
                icon.name: "dialog-ok-apply"
                enabled: win.canCommit && win.flowState !== "committing"
                onClicked: win.run("apply")
            }
            QQC2.Button {
                text: Tr.tr("OK")
                icon.name: "dialog-ok"
                enabled: win.canCommit && win.flowState !== "committing"
                onClicked: win.run("ok")
            }
        }
    }
}
