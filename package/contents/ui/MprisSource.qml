// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.private.mpris as Mpris
import "players.js" as Players

// The only file that imports Plasma's private MPRIS module. It is loaded
// through a Loader, so if a Plasma update changes that module only this file
// fails and main.qml falls back to the helper's D-Bus reader.
Item {
    id: root

    property var preferred: []
    // Identity picked in the widget's menu, "" = automatic
    property string pinned: ""

    readonly property var media: player ? {
        track: player.track || "",
        artist: player.artist || "",
        album: player.album || "",
        artUrl: player.artUrl ? player.artUrl.toString() : "",
        identity: player.identity || "",
        position: player.position,
        length: player.length,
        rate: player.rate || 1,
        playing: player.playbackStatus === Mpris.PlaybackStatus.Playing,
        // what this player says it can do; controls follow these
        canControl: player.canControl,
        canPlayPause: player.canControl && (player.canPause || player.canPlay),
        canGoNext: player.canGoNext,
        canGoPrevious: player.canGoPrevious,
        canSeek: player.canSeek,
        canRaise: player.canRaise,
        // null: the player doesn't have it (Firefox, Chromium), so no button
        shuffle: player.shuffle === Mpris.ShuffleStatus.Unknown ? null : player.shuffle === Mpris.ShuffleStatus.On,
        loop: loopName(player.loopStatus)
    } : null

    function loopName(status) {
        switch (status) {
        case Mpris.LoopStatus.None: return "None";
        case Mpris.LoopStatus.Playlist: return "Playlist";
        case Mpris.LoopStatus.Track: return "Track";
        default: return null;
        }
    }

    function sync() {
        if (player)
            player.updatePosition();
    }

    // "playPause" | "next" | "previous" | "raise" | "seek" (value: µs) |
    // "volume" (value: ±0..1) | "shuffle" (value: bool) | "loop" (value: "None" | "Playlist" | "Track")
    function act(action, value) {
        if (!player)
            return;
        switch (action) {
        case "playPause": player.PlayPause(); break;
        case "next": player.Next(); break;
        case "previous": player.Previous(); break;
        case "raise": player.Raise(); break;
        // the container sends SetPosition with the current track id
        case "seek": player.position = value; break;
        case "volume": player.changeVolume(value, true); break;
        case "shuffle":
            if (media.shuffle !== null && media.canControl && typeof value === "boolean")
                player.shuffle = value ? Mpris.ShuffleStatus.On : Mpris.ShuffleStatus.Off;
            break;
        case "loop":
            if (media.loop !== null && media.canControl && Players.LOOP_STATUSES.includes(value))
                player.loopStatus = value === "Track" ? Mpris.LoopStatus.Track
                    : value === "Playlist" ? Mpris.LoopStatus.Playlist : Mpris.LoopStatus.None;
            break;
        }
    }

    Mpris.Mpris2Model {
        id: mpris
    }

    Instantiator {
        id: players
        model: mpris
        delegate: QtObject {
            required property var container
        }
    }

    // every open player, for the selection and the menu
    readonly property var containers: {
        mpris.currentPlayer; // re-evaluate when players change
        players.count;
        let list = [];
        for (let i = 0; i < players.count; i++) {
            const o = players.objectAt(i);
            if (o && o.container)
                list.push(o.container);
        }
        return list;
    }
    readonly property var playerList: containers.map(c => ({
        identity: c.identity || "",
        desktopEntry: c.desktopEntry || "",
        playing: c.playbackStatus === Mpris.PlaybackStatus.Playing
    }))

    readonly property var player: {
        const chosen = Players.pick(playerList, pinned, preferred, false);
        return chosen ? containers[playerList.indexOf(chosen)] : mpris.currentPlayer;
    }
}
