// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtWebSockets
import "net.js" as Net

// Connection to helper.py (launched on demand, shared by every widget).
Item {
    id: root

    signal configReceived(var data, var issues)
    signal designReceived(var web)
    signal schemaReceived(var schema)
    signal barsReceived(var values)
    signal appsReceived(var apps)
    signal mediaReceived(var data)
    // open players, for the widget's menu (D-Bus mode only)
    signal playersReceived(var list)
    // result of exportPreset / importPreset: { op, error?, name?, ignored? }
    signal presetFileReceived(var result)
    signal presetsReceived(var list)
    signal editStateReceived(var state)

    // An older helper is still running (it survived an update). One the
    // widget started is asked to quit, and the next retry starts the new
    // one; the systemd service ignores that, so it is reported instead.
    property bool outdatedService: false
    property bool askedToQuit: false

    // empty = receive everything (the widget); settings pages pass
    // ["config", "schema"] so they don't get the 60 fps bar stream
    property var topics: []

    // from NPV_PORT, like the helper. The socket waits until it is known, so
    // the widget never talks to whatever holds the default port meanwhile.
    property int port: Net.DEFAULT_PORT
    property bool portKnown: false
    property bool portAsked: false
    readonly property string url: Net.helperUrl(port)

    readonly property bool connected: socket.status === WebSocket.Open
    onConnectedChanged: {
        if (connected && topics.length)
            send({ type: "subscribe", topics: topics });
    }
    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/helper.py").toString().replace("file://", ""))

    function send(obj) {
        if (connected)
            socket.sendTextMessage(JSON.stringify(obj));
    }

    function usePort(text) {
        if (portKnown)
            return;
        port = Net.parsePort(text);
        if (text !== "" && String(port) !== text)
            console.warn(`nowplayingvisualizer: ignoring NPV_PORT, not a port between ${Net.MIN_PORT} and ${Net.MAX_PORT}; using ${port}`);
        portKnown = true;
        portTimeout.stop();
        socket.active = true;
    }

    function findPort() {
        if (portKnown || portAsked)
            return;
        if (launcher.status === Loader.Ready) {
            portAsked = true;
            portTimeout.start();
            launcher.item.readPort();
        } else if (launcher.status === Loader.Error) {
            usePort("");
        }
    }

    function launch() {
        if (launcher.item)
            launcher.item.launch(helperPath);
    }

    WebSocket {
        id: socket
        url: root.url
        active: false
        onTextMessageReceived: message => {
            if (message.charAt(0) === "B") {
                root.barsReceived(Net.parseBars(message));
                return;
            }
            const m = Net.parseMessage(message);
            if (!m)
                return;
            if (m.type === "config") {
                root.configReceived(m.data, m.issues || []);
                root.designReceived(m.web || {});
            }
            else if (m.type === "schema") {
                const old = Net.outdated(m);
                root.outdatedService = old && m.service === true;
                if (old && !root.outdatedService && !root.askedToQuit) {
                    console.warn("nowplayingvisualizer: an older helper is running, restarting it");
                    root.askedToQuit = true;
                    root.send({ type: "quit" });
                }
                root.schemaReceived(m.data);
            }
            else if (m.type === "apps")
                root.appsReceived(m.data);
            else if (m.type === "media") {
                root.mediaReceived(m.data);
                if (Array.isArray(m.players))
                    root.playersReceived(m.players);
            }
            else if (m.type === "presetFile")
                root.presetFileReceived(m);
            else if (m.type === "presets")
                root.presetsReceived(m.data);
            else if (m.type === "editState")
                root.editStateReceived(m);
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

    // Plasma5Support stuck: go on with the default port
    Timer {
        id: portTimeout
        interval: 3000
        onTriggered: root.usePort("")
    }

    Loader {
        id: launcher
        source: "Launcher.qml"
        onStatusChanged: root.findPort()
    }
    Connections {
        target: launcher.item
        function onPortRead(text) {
            root.usePort(text);
        }
    }

    Component.onCompleted: findPort()
}
