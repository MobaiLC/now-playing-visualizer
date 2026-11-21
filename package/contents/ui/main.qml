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

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    NowPlaying {
        id: nowPlaying
        pinnedPlayer: Plasmoid.configuration.pinnedPlayer
    }

    // ---- player menu ----------------------------------------------------------
    // Right-click > pick a player: the widget then shows that one while it is
    // open (automatic otherwise). Saved per widget; NowPlaying tells the helper,
    // so the D-Bus fallback and "Follow the player" pick the same one.
    readonly property var playerMenu: Players.menu(nowPlaying.openPlayers, nowPlaying.pinnedPlayer)

    function pinPlayer(identity) {
        Plasmoid.configuration.pinnedPlayer = identity;
    }
    PlasmaCore.Action {
        id: playerHeading
        text: i18n("Show the player")
        isSeparator: true
    }
    PlasmaCore.Action {
        id: autoPlayer
        text: i18n("Automatic (the one playing)")
        checkable: true
        checked: nowPlaying.pinnedPlayer === ""
        onTriggered: root.pinPlayer("")
    }
    Instantiator {
        id: playerActions
        model: root.playerMenu
        delegate: PlasmaCore.Action {
            required property var modelData
            text: modelData.open ? modelData.identity : i18n("%1 (not open)", modelData.identity)
            checkable: true
            checked: nowPlaying.pinnedPlayer.toLowerCase() === modelData.identity.toLowerCase()
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

    // Apply/OK in the Design page: keep the live-edited design (see helper.py)
    readonly property string designCommit: Plasmoid.configuration.designCommit
    onDesignCommitChanged: nowPlaying.send({ type: "commitEdit" })

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
            active: nowPlaying.ready
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
            visible: nowPlaying.shownIssues.length > 0
            source: "dialog-warning"
            HoverHandler {
                id: issueHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: Plasmoid.internalAction("configure").trigger()
            }
            QQC2.ToolTip.visible: issueHover.hovered
            QQC2.ToolTip.text: nowPlaying.shownIssues.map(root.issueText).join("\n") + "\n\n" + i18n("Click to open the settings")
        }

        Component {
            id: card
            Card {
                anchors.fill: parent
                cfg: nowPlaying.cfg
                media: nowPlaying.shownMedia
                listeningText: i18n("Listening to {title}")
                nothingPlayingText: i18n("Nothing playing")
                showProgress: nowPlaying.hasTrack
                positionMs: nowPlaying.positionMs
                lengthMs: nowPlaying.lengthMs
                barValues: nowPlaying.barValues
                onAction: (name, value) => nowPlaying.mediaAction(name, value)
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
