// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtWebSockets

// Connection to helper.py (launched on demand, shared by every widget).
Item {
    id: root

    signal configReceived(var data, var issues)
    signal designReceived(var web)
    signal schemaReceived(var schema)
    signal barsReceived(var values)
    signal appsReceived(var apps)
    signal mediaReceived(var data)

    readonly property bool connected: socket.status === WebSocket.Open
    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/helper.py").toString().replace("file://", ""))

    function send(obj) {
        if (connected)
            socket.sendTextMessage(JSON.stringify(obj));
    }

    function launch() {
        if (launcher.item)
            launcher.item.launch(helperPath);
    }

    WebSocket {
        id: socket
        url: "ws://127.0.0.1:47811"
        active: false
        onTextMessageReceived: message => {
            if (message.charAt(0) === "B") {
                root.barsReceived(message.slice(1).split(";").map(Number));
                return;
            }
            const m = JSON.parse(message);
            if (m.type === "config") {
                root.configReceived(m.data, m.issues || []);
                root.designReceived(m.web || {});
            }
            else if (m.type === "schema")
                root.schemaReceived(m.data);
            else if (m.type === "apps")
                root.appsReceived(m.data);
            else if (m.type === "media")
                root.mediaReceived(m.data);
        }
        onStatusChanged: {
            if (socket.status === WebSocket.Error || socket.status === WebSocket.Closed) {
                active = false;
                retry.start();
            }
        }
    }

    Timer {
        id: retry
        interval: 1500
        onTriggered: {
            root.launch();
            socket.active = true;
        }
    }

    Loader {
        id: launcher
        source: "Launcher.qml"
    }

    Component.onCompleted: socket.active = true
}
