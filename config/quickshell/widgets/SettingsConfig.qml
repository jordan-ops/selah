pragma Singleton
import QtQuick
import Quickshell
import "../services" as Services

// Config bridge for the ported Nebula widgets (Nebula shell, GPL-3.0).
//
// Upstream, everything widget-related lives in ONE settings.json object:
// SettingsConfig.widgets — read as a plain JS object, written by reassigning
// the whole blob (SettingsConfig.widgets = Object.assign({}, …, patch)).
// Our store is a flat key/value map that the Settings app's switch/choice
// rows bind on directly, so this singleton is the two-way translator:
//
//   blob  = defaults  +  every flat key under "widgets."
//   a blob reassignment is diffed against the last build and only the
//   CHANGED keys are flushed back — one atomic Settings.setAll(), so a
//   drag that lands three keys still writes the file once, and defaults
//   never spam settings.json (they stay implicit until a user changes one).
//
// `general` and `weather` mirror the small slices upstream widgets read,
// answered from this shell's services (fonts follow set-font.sh live;
// desktop ripples stay disabled because Background.qml owns ours).
Singleton {
    id: root

    // ── widgets: the persisted blob ───────────────────────────────────
    // Defaults mirror Nebula's SettingsConfig.widgets, minus the families
    // we didn't port (personal/news/lyrics/spectrum/claude/photo) and with
    // positions kept for every ported family so nothing lands at 0,0.
    readonly property var defaults: ({
        showWidgets: true,
        cardStyle: "flat",
        cardOpacity: 0.60,
        blurBackground: false,

        // digital clock family
        showClock: false,
        digitalClockStyle: "veil",
        clockX: 100, clockY: 100,
        clockUse24: false, clockShowDate: true, clockStatus: true,
        clockSpin: true, clockSeconds: true, clockMusicRim: true,
        clockTilt: true, clockAlignLeft: false, clockLabel: true,
        clockShapeLock: "",

        // analog + date families
        showAnalogClock: false, analogClockStyle: "classic",
        analogClockX: 400, analogClockY: 200, analogShapeLock: "",
        showDateWidget: false, dateWidgetStyle: "bold",
        dateWidgetX: 300, dateWidgetY: 300, dateShapeLock: "",

        // weather
        showWeatherForecast: false, weatherForecastX: 420, weatherForecastY: 200,
        showWeatherHourly: false, weatherHourlyX: 420, weatherHourlyY: 200,
        showSunArc: false, sunArcX: 100, sunArcY: 620,
        showMoonPhase: false, moonPhaseX: 620, moonPhaseY: 440,
        showWeatherShape: false, weatherShapeX: 660, weatherShapeY: 200,
        weatherShapeLock: "",

        // calendar
        showCalendarMini: false, calendarMiniX: 420, calendarMiniY: 300,
        calendarMiniMonday: true, calendarMiniDimOther: true,
        showCalendarYarn: false, calendarYarnX: 660, calendarYarnY: 300,
        calendarYarnMonday: true, calendarYarnFooter: true,
        showCalendarAlmanac: false, calendarAlmanacX: 880, calendarAlmanacY: 300,
        calendarAlmanacMonday: true, calendarAlmanacDimOther: true,
        showCalendarTorn: false, calendarTornX: 1120, calendarTornY: 300,
        calendarTornMonday: true, calendarTornStrip: true,
        showCalendarWindows: false, calendarWindowsX: 420, calendarWindowsY: 440,
        calendarWindowsMonday: true, calendarWindowsFooter: true,
        showCalendarDaylight: false, calendarDaylightX: 420, calendarDaylightY: 100,
        calendarDaylightPlace: true,
        showCalendarYear: false, calendarYearX: 760, calendarYearY: 440,
        calendarYearHolidays: true,
        showCalendarStamp: false, calendarStampX: 1100, calendarStampY: 440,
        calendarStampPostmark: true,
        showCalendarMoon: false, calendarMoonX: 760, calendarMoonY: 100,
        calendarMoonMonday: true,

        // productivity
        showTaskList: false, taskListX: 960, taskListY: 200,
        showStickyNote: false, stickyNoteX: 620, stickyNoteY: 660,
        stickyNoteText: "",
        showPomodoro: false, pomodoroX: 145, pomodoroY: 605,
        showWorldClock: false, worldClockX: 880, worldClockY: 440,
        worldClockZones: [
            { label: "Local", tz: "" },
            { label: "Tokyo", tz: "Asia/Tokyo" },
            { label: "London", tz: "Europe/London" }
        ],
        worldClockShapeLock: "",

        // system
        showSystemMonitor: false, systemMonitorStyle: "default",
        sysMonitorX: 145, sysMonitorY: 165,
        showBattery: false, batteryStyle: "ring",
        batteryX: 620, batteryY: 620, batteryShapeLock: "",
        showNetworkGraph: false, networkGraphX: 100, networkGraphY: 780,
        networkGraphWindow: "3 min", networkGraphInterval: "2 s",
        showSysCockpit: false, sysCockpitX: 145, sysCockpitY: 165,
        showSysBlueprint: false, sysBlueprintX: 695, sysBlueprintY: 165,
        showSysVitals: false, sysVitalsX: 145, sysVitalsY: 495,
        showSysForecast: false, sysForecastX: 695, sysForecastY: 495,
        showSysFlask: false, sysFlaskX: 145, sysFlaskY: 400,
        showSysThermo: false, sysThermoX: 365, sysThermoY: 165,
        showSysCreature: false, sysCreatureX: 540, sysCreatureY: 300,
        showSysCells: false, sysCellsX: 585, sysCellsY: 165,
        showSysShape: false, sysShapeX: 805, sysShapeY: 165,
        showSysHourglass: false, sysHourglassX: 1025, sysHourglassY: 165,
        showSysFillNumber: false, sysFillNumberX: 1245, sysFillNumberY: 165,
        sysFillMetric: "cpu",

        // music
        showMusicExpressive: false, musicExpressiveX: 145, musicExpressiveY: 605,
        showMusicTicket: false, musicTicketX: 585, musicTicketY: 605,
        showMusicPoster: false, musicPosterX: 475, musicPosterY: 165,
        showMusicTuner: false, musicTunerX: 585, musicTunerY: 825,
        showMusicWaveform: false, musicWaveformX: 1025, musicWaveformY: 605,
        showMusicCapsule: false, musicCapsuleX: 145, musicCapsuleY: 935,
        showMusicGlance: false, musicGlanceX: 695, musicGlanceY: 935,
        showMusicFlap: false, musicFlapX: 1025, musicFlapY: 825,
        showMusicBento: false, musicBentoX: 1245, musicBentoY: 385,
        showMusicRibbon: false, musicRibbonX: 35, musicRibbonY: 165,
        showMusicNeon: false, musicNeonX: 585, musicNeonY: 385,
        showMusicTerminal: false, musicTerminalX: 145, musicTerminalY: 385
    })

    property var widgets: ({})
    // last build — the baseline a blob reassignment is diffed against
    property var _built: ({})

    function syncFromStore() {
        const next = Object.assign({}, root.defaults)
        const vals = Services.Settings.values
        for (const k in vals) {
            if (k.lastIndexOf("widgets.", 0) === 0) next[k.slice(8)] = vals[k]
        }
        root._built = next
        if (JSON.stringify(next) !== JSON.stringify(root.widgets))
            root.widgets = next
    }

    function flatten() {
        const vals = Services.Settings.values
        const patch = {}
        let n = 0
        // keys the caller changed relative to the last build
        for (const k in root.widgets) {
            if (root.widgets[k] !== root._built[k]) {
                patch["widgets." + k] = root.widgets[k]
                n++
            }
        }
        // keys the caller dropped (WidgetCatalog.resetLayout deletes X/Y/W/H)
        for (const k in root._built) {
            if (!(k in root.widgets)) {
                patch["widgets." + k] = undefined
                n++
            }
        }
        // one atomic write; the FileView watch brings us back through
        // onValuesChanged, which rebuilds _built and settles the diff
        if (n > 0) Services.Settings.setAll(patch)
    }

    onWidgetsChanged: {
        // syncFromStore reassigns widgets itself — only user-side writes
        // (Object.assign patterns in host/studio) must flush
        if (JSON.stringify(root.widgets) !== JSON.stringify(root._built))
            root.flatten()
    }

    Component.onCompleted: syncFromStore()

    Connections {
        target: Services.Settings
        function onValuesChanged() { root.syncFromStore() }
    }

    // ── general: the small slice widgets read ─────────────────────────
    readonly property var general: ({
        // live: follows set-font.sh / Settings ▸ Fonts with no rewire
        get defaultFont() { return Services.Fonts.family },
        get displayFont() { return Services.Fonts.family },
        get fontScale() { return "normal" },
        get fontWeight() { return "extrabold" },
        get motionScheme() { return "expressive" },
        // Background.qml owns desktop ripples — the widget layer keeps its
        // own MouseArea disabled (upstream default is the same, false)
        get desktopRipple() { return false },
        get desktopRippleDrag() { return true },
        get profile() { return ({ name: "", status: "", avatar: "" }) }
    })

    // ── weather: unit preference only; data flows through services/Weather
    readonly property var weather: ({
        useMetric: true,
        location: "",
        refreshInterval: 15
    })
}
