pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// wttr.in weather for the bar's activity chip. One JSON fetch every 30
// minutes (or on demand — clicking the chip), cached to disk so the
// last reading survives quickshell reloads and offline stretches.
Singleton {
    id: root

    readonly property string cachePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/weather.json"

    property string temp: ""     // "23"
    property string desc: ""     // "Partly cloudy"
    readonly property bool ok: temp !== ""
    readonly property string tempLabel: temp !== "" ? temp + "°" : ""

    // condition → emoji, checked specific-first so "partly cloudy"
    // doesn't fall through to the plain-cloud branch. `kind` is the
    // shared classifier: the glyph maps from it and the clock card's
    // weather canvas picks its animation from it too.
    readonly property string kind: {
        const d = desc.toLowerCase()
        if (d.includes("thunder")) return "thunder"
        if (d.includes("snow") || d.includes("blizzard") || d.includes("sleet")) return "snow"
        if (d.includes("rain") || d.includes("drizzle") || d.includes("shower")) return "rain"
        if (d.includes("fog") || d.includes("mist") || d.includes("haze")) return "fog"
        if (d.includes("partly")) return "partly"
        if (d.includes("clear") || d.includes("sunny")) return "sun"
        if (d.includes("cloud") || d.includes("overcast")) return "cloud"
        return "partly"
    }
    readonly property string glyph: ({
        thunder: "⛈️", snow: "❄️", rain: "🌧️", fog: "🌫️",
        partly: "⛅", sun: "☀️", cloud: "☁️"
    })[kind] || "⛅"
    readonly property real tempNum: temp !== "" ? parseFloat(temp) : 0

    FileView {
        path: root.cachePath
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (d && d.t) {
                    root.temp = d.t
                    root.desc = d.d || ""
                }
            } catch (e) {
                console.log("Weather: cache parse —", e)
            }
        }
    }

    Process { id: wr }   // cache writer (argv-form, same as Battery history)

    function persist() {
        wr.command = ["sh", "-c", "printf %s \"$1\" > \"$2\"", "wwrite",
                      JSON.stringify({ t: root.temp, d: root.desc }), root.cachePath]
        wr.running = false
        wr.running = true
    }

    Process {
        id: fetch
        command: ["curl", "-sf", "-m", "8", "https://wttr.in/?format=j1"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") return   // curl failed — keep last reading
                try {
                    const j = JSON.parse(text)
                    const cc = j.current_condition && j.current_condition[0]
                    if (!cc) return
                    root.temp = cc.temp_C
                    const vd = cc.weatherDesc && cc.weatherDesc[0]
                    root.desc = vd ? vd.value : ""
                    root.persist()
                } catch (e) {
                    console.log("Weather: parse —", e)
                }
            }
        }
    }

    function refresh() {
        fetch.running = false
        fetch.running = true
    }

    Timer {
        interval: 1800000   // 30 min
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
