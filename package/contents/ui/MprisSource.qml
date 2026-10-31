// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.private.mpris as Mpris

// The only file that imports Plasma's private MPRIS module. It is loaded
// through a Loader, so if a Plasma update changes that module only this file
// fails and main.qml falls back to the helper's D-Bus reader.
Item {
    id: root

    property var preferred: []

    readonly property var media: player ? {
        track: player.track || "",
        artist: player.artist || "",
        album: player.album || "",
        artUrl: player.artUrl ? player.artUrl.toString() : "",
        identity: player.identity || "",
        position: player.position,
        length: player.length,
        rate: player.rate || 1,
        playing: player.playbackStatus === Mpris.PlaybackStatus.Playing
    } : null

    function sync() {
        if (player)
            player.updatePosition();
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

    function isPreferred(p) {
        const names = (preferred || []).map(n => n.toLowerCase());
        const id = ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase();
        return names.some(n => id.includes(n));
    }

    readonly property var player: {
        mpris.currentPlayer; // re-evaluate when players change
        players.count;
        let list = [];
        for (let i = 0; i < players.count; i++) {
            const o = players.objectAt(i);
            if (o && o.container)
                list.push(o.container);
        }
        const playing = p => p.playbackStatus === Mpris.PlaybackStatus.Playing;
        return list.find(p => playing(p) && isPreferred(p))
            || list.find(p => playing(p))
            || list.find(p => isPreferred(p))
            || mpris.currentPlayer;
    }
}
