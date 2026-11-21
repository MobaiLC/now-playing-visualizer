// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "ui"
import "ui/desktop.js" as Desktop

// The desktop card for Hyprland (or any layer-shell compositor):
//   quickshell -p <package>/contents/quickshell
// "ui" is a symlink to ../ui: quickshell refuses imports outside this folder.
ShellRoot {
    NowPlaying {
        id: nowPlaying
    }

    // right-click on the card opens the settings window (own file, found from this one)
    Process {
        id: settingsWindow
        command: ["python3", "-I", Qt.resolvedUrl("../code/cli.py").toString().replace("file://", ""), "settings"]
    }

    readonly property var desk: nowPlaying.cfg.desktop

    // built once the helper has sent desktop.* (an older helper never does)
    LazyLoader {
        active: desk !== undefined

        PanelWindow {
            // Quickshell.screens is read here, so a new or removed screen re-picks
            screen: Desktop.pickScreen(Quickshell.screens, desk.monitor)
            anchors: Desktop.anchorsFor(desk.anchor)
            margins {
                left: desk.marginX
                right: desk.marginX
                top: desk.marginY
                bottom: desk.marginY
            }
            implicitWidth: desk.width
            implicitHeight: desk.height
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "nowplaying-viz"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Loader {
                anchors.fill: parent
                active: nowPlaying.ready
                sourceComponent: Card {
                    cfg: nowPlaying.cfg
                    media: nowPlaying.shownMedia
                    showProgress: nowPlaying.hasTrack
                    positionMs: nowPlaying.positionMs
                    lengthMs: nowPlaying.lengthMs
                    barValues: nowPlaying.barValues
                    onAction: (name, value) => nowPlaying.mediaAction(name, value)
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: settingsWindow.running = true
                    }
                    opacity: nowPlaying.hasTrack && nowPlaying.isPlaying ? 1
                        : !nowPlaying.hasTrack && nowPlaying.whenIdle === "hide" ? 0
                        : nowPlaying.panelCfg.idleOpacity
                    Behavior on opacity {
                        NumberAnimation { duration: 500 }
                    }
                }
            }
        }
    }
}
