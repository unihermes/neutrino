// Neutrino - Quickshell
// ~/.config/quickshell/Media.qml
//
// The MPRIS player the bar's media module follows: whichever is playing,
// else the last one that was, else the first one there is. Browsers expose
// a player per tab that has ever had media, so "the first one" alone would
// often pick a silent tab over the song that's actually on.

pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    property var lastPlaying: null

    readonly property var players: Mpris.players.values

    readonly property var player: {
        var ps = players
        for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
        if (lastPlaying && ps.indexOf(lastPlaying) !== -1) return lastPlaying
        return ps.length > 0 ? ps[0] : null
    }

    onPlayerChanged: if (player && player.isPlaying) lastPlaying = player

    Connections {
        target: root.player
        function onIsPlayingChanged() { if (root.player.isPlaying) root.lastPlaying = root.player }
    }

    function fmtTime(sec) {
        if (!(sec >= 0)) return "--:--"
        var m = Math.floor(sec / 60), s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }
}
