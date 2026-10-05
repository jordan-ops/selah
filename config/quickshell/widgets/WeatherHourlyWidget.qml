// Ported from Nebula's Widgets/WeatherHourlyWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts

// Today's temperature curve with rain chance underneath.
//
// ServiceWeather already fetches the hourly forecast and nothing displayed it —
// the other weather widgets all show a single moment. Temperatures arrive as
// strings with the degree sign attached, so they have to be stripped before
// anything can be plotted.
WidgetHost {
    id: root
    configKey: "weatherHourly"
    tile: WidgetSizes.wide
    resizable: true
    minSpan: Qt.size(3, 2)
    maxSpan: Qt.size(6, 4)
    defaultPos: Qt.point(420, 200)

    readonly property bool metric: SettingsConfig.weather.useMetric ?? true

    readonly property bool showCity: root.cols >= 4
    readonly property bool showStats: root.rows >= 2.5
    readonly property bool showForecast: root.rows >= 3

    readonly property var hours: {
        const h = ServiceWeather.todayHourly ?? []
        var out = []
        for (var i = 0; i < h.length; i++) {
            const raw = root.metric ? h[i].tempC : h[i].tempF
            const t = parseInt(String(raw).replace("°", ""), 10)
            if (isNaN(t)) continue
            out.push({
                time: h[i].time,
                temp: t,
                rain: parseInt(h[i].chanceofrain ?? 0, 10) || 0
            })
        }
        return out
    }

    readonly property bool hasData: root.hours.length >= 2

    // Horizontal inset of the plot area, shared by the canvas and the hour
    // labels so a label sits under the point it names.
    readonly property int chartPadX: 7

    readonly property int minTemp: {
        if (!root.hasData) return 0
        var m = root.hours[0].temp
        for (var i = 1; i < root.hours.length; i++) m = Math.min(m, root.hours[i].temp)
        return m
    }
    readonly property int peakRain: {
        if (!root.hasData) return 0
        var m = 0
        for (var i = 0; i < root.hours.length; i++) m = Math.max(m, root.hours[i].rain)
        return m
    }

    readonly property var gridTemps: {
        if (!root.hasData) return []
        const mid = Math.round((root.minTemp + root.maxTemp) / 2)
        const out = [root.minTemp]
        if (mid !== root.minTemp && mid !== root.maxTemp) out.push(mid)
        if (root.maxTemp !== root.minTemp) out.push(root.maxTemp)
        return out
    }

    readonly property int maxTemp: {
        if (!root.hasData) return 0
        var m = root.hours[0].temp
        for (var i = 1; i < root.hours.length; i++) m = Math.max(m, root.hours[i].temp)
        return m
    }

    function dayName(day, index) {
        if (index === 0) return "Today"
        if (!day || !day.date) return "—"
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(day.date).getDay()]
    }

    function dayIcon(day) {
        if (!day || !day.hourly || day.hourly.length === 0) return ""
        const h = day.hourly[Math.min(4, day.hourly.length - 1)]
        return IconUtil.getSystemIcon(ServiceWeather.getWeatherIcon(h.weatherCode, false).svg)
    }

    WidgetCard {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: parent.pad
            anchors.rightMargin: parent.pad
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            spacing: 6
            visible: root.hasData

            // ── Header ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 6
                spacing: 6

                Image {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    sourceSize.width: 40
                    sourceSize.height: 40
                    asynchronous: true
                    source: IconUtil.getSystemIcon(ServiceWeather.weatherIconPath.svg)
                }

                CustomText {
                    content: ServiceWeather.temperature
                    size: 15
                    weight: 700
                    customColor: Colors.surfaceText
                }

                CustomText {
                    Layout.fillWidth: true
                    content: ServiceWeather.description
                           + (root.showCity ? " · " + ServiceWeather.cityName : "")
                    size: 12
                    customColor: Colors.outline
                    elide: Text.ElideRight
                }

                MaterialIconSymbol {
                    visible: root.peakRain > 0
                    content: "water_drop"
                    iconSize: 12
                    customColor: Colors.tertiary
                }

                CustomText {
                    visible: root.peakRain > 0
                    content: root.peakRain + "%"
                    size: 12
                    customColor: Colors.tertiary
                }

                CustomText {
                    content: root.maxTemp + "° / " + root.minTemp + "°"
                    size: 12
                    customColor: Colors.outline
                }
            }

            // ── Chart ─────────────────────────────────────────────────
            TrapezoidChart {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 4

                readonly property int labelStep: root.cols >= 5 ? 1 : 2

                values: root.hours.map(h => h.temp)
                labels: root.hours.map((h, i) => i % labelStep === 0 ? h.time.replace(" ", "") : "")

                lo: root.minTemp - Math.max(2, Math.round((root.maxTemp - root.minTemp) * 0.4))
                hi: root.maxTemp + 1
                gridValues: root.gridTemps
                suffix: "°"
                barColor: Colors.primary
            }

            // ── Current details ───────────────────────────────────────
            RowLayout {
                visible: root.showStats
                Layout.fillWidth: true
                Layout.rightMargin: 6
                spacing: 0

                Repeater {
                    model: [
                        { icon: "thermostat",   value: "Feels " + ServiceWeather.feelsLike },
                        { icon: "humidity_mid", value: Math.round(ServiceWeather.humidity) + "%" },
                        { icon: "air",          value: ServiceWeather.windSpeed },
                        { icon: "wb_sunny",     value: "UV " + ServiceWeather.uvindex }
                    ]

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 5

                        MaterialIconSymbol {
                            content: modelData.icon
                            iconSize: 13
                            customColor: Colors.primary
                        }
                        CustomText {
                            content: modelData.value
                            size: 12
                            customColor: Colors.surfaceText
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // ── Next days ─────────────────────────────────────────────
            Rectangle {
                visible: root.showForecast
                Layout.fillWidth: true
                Layout.rightMargin: 6
                implicitHeight: 1
                color: Colors.outlineVariant
                opacity: 0.4
            }

            RowLayout {
                visible: root.showForecast
                Layout.fillWidth: true
                Layout.rightMargin: 6
                spacing: 0

                Repeater {
                    model: Math.min(3, ServiceWeather.forecastDays?.length ?? 0)

                    delegate: RowLayout {
                        required property int index
                        readonly property var day: ServiceWeather.forecastDays[index]
                        Layout.fillWidth: true
                        spacing: 6

                        CustomText {
                            content: root.dayName(day, index)
                            size: 12
                            weight: 600
                            customColor: index === 0 ? Colors.primary : Colors.outline
                        }

                        Image {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            sourceSize.width: 36
                            sourceSize.height: 36
                            asynchronous: true
                            source: root.dayIcon(day)
                        }

                        CustomText {
                            content: (root.metric ? day?.maxtempC : day?.maxtempF) + "°"
                            size: 12
                            weight: 700
                            customColor: Colors.surfaceText
                        }

                        CustomText {
                            content: (root.metric ? day?.mintempC : day?.mintempF) + "°"
                            size: 11
                            customColor: Colors.outline
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }

        // ── Empty state ───────────────────────────────────────────────
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8
            visible: !root.hasData

            MaterialIconSymbol {
                Layout.alignment: Qt.AlignHCenter
                content: "cloud_off"
                iconSize: 26
                customColor: Colors.outline
            }
            CustomText {
                Layout.alignment: Qt.AlignHCenter
                content: "No hourly forecast"
                size: 12
                customColor: Colors.outline
            }
        }
    }
}
