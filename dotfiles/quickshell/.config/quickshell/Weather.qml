// Neutrino - Quickshell
// ~/.config/quickshell/Weather.qml
//
// Current conditions and a 3-day forecast from wttr.in, for the bar's
// weather module and its flyout.
//
// wttr.in because it needs no API key and no configured location: with no
// place in the URL it geolocates the request's IP, which is right for a
// laptop that moves around. Refreshed every 30 minutes -- weather doesn't
// change faster than that, and wttr.in rate-limits clients that poll hard.
// On failure the last good reading is kept rather than blanked.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool ready: false
    property string area: ""
    property int code: 0
    property string condition: ""
    property real tempF: 0
    property real tempC: 0
    property real feelsF: 0
    property real feelsC: 0
    property int humidity: 0
    property string wind: ""
    property bool isNight: false
    // [{ date, hiF, loF, hiC, loC, code, condition }]
    property var forecast: []
    property var updated: null
    property bool failed: false

    readonly property bool metric: Settings.weatherUnits === "C"

    function temp(f, c) { return Math.round(metric ? c : f) + "°" }

    function refresh() { if (!fetch.running) fetch.running = true }

    // WWO weather codes (what wttr.in returns) to Material Design glyphs
    function iconFor(c, night) {
        if (c === 113) return night ? "󰖔" : "󰖙"
        if (c === 116) return night ? "󰼱" : "󰖕"
        if (c === 119 || c === 122) return "󰖐"
        if ([143, 248, 260].indexOf(c) !== -1) return "󰖑"
        if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return "󰙾"
        if ([227, 230, 323, 326, 329, 332, 335, 338, 368, 371].indexOf(c) !== -1) return "󰖘"
        if ([179, 182, 185, 281, 284, 311, 314, 317, 350, 362, 365, 374, 377].indexOf(c) !== -1) return "󰙿"
        if ([299, 302, 305, 308, 356, 359].indexOf(c) !== -1) return "󰖖"
        return "󰖗"   // the light/patchy rain codes, and anything unlisted
    }

    // "06:59 AM" -> minutes after midnight
    function minutesOf(t) {
        var m = String(t).match(/(\d+):(\d+)\s*(AM|PM)/i)
        if (!m) return -1
        var h = Number(m[1]) % 12
        if (m[3].toUpperCase() === "PM") h += 12
        return h * 60 + Number(m[2])
    }

    Process {
        id: fetch
        command: ["curl", "-sf", "--max-time", "15", "https://wttr.in/?format=j1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    var c = d.current_condition[0]
                    var a = d.nearest_area && d.nearest_area[0]
                    root.area = a ? a.areaName[0].value + ", " + a.region[0].value : ""
                    root.code = Number(c.weatherCode)
                    root.condition = c.weatherDesc[0].value.trim()
                    root.tempF = Number(c.temp_F); root.tempC = Number(c.temp_C)
                    root.feelsF = Number(c.FeelsLikeF); root.feelsC = Number(c.FeelsLikeC)
                    root.humidity = Number(c.humidity)
                    root.wind = c.windspeedMiles + " mph " + c.winddir16Point

                    var astro = d.weather[0].astronomy[0]
                    var now = new Date(), mins = now.getHours() * 60 + now.getMinutes()
                    var rise = root.minutesOf(astro.sunrise), set = root.minutesOf(astro.sunset)
                    root.isNight = rise >= 0 && set >= 0 && (mins < rise || mins >= set)

                    var f = []
                    for (var i = 0; i < d.weather.length; i++) {
                        var w = d.weather[i]
                        // midday (the 12:00 slot) stands in for the day
                        var noon = w.hourly[Math.min(4, w.hourly.length - 1)]
                        f.push({ date: w.date, hiF: Number(w.maxtempF), loF: Number(w.mintempF),
                                 hiC: Number(w.maxtempC), loC: Number(w.mintempC),
                                 code: Number(noon.weatherCode), condition: noon.weatherDesc[0].value.trim() })
                    }
                    root.forecast = f
                    root.updated = new Date()
                    root.ready = true
                    root.failed = false
                } catch (e) {
                    root.failed = true
                }
            }
        }
        onExited: code => { if (code !== 0) root.failed = true }
    }

    Timer {
        interval: 1800000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
