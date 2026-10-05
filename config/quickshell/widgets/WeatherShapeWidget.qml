// Ported from Nebula's Widgets/WeatherShapeWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "shapes/material-shapes.js" as MaterialShapeFn
import "shapes/shape-library.js" as ShapeLibrary

ShapeWidget {
    id: root
    configKey: "weatherShape"
    tile: WidgetSizes.small
    resizable: true
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    defaultPos: Qt.point(660, 200)

    readonly property string shapeLock: SettingsConfig.widgets.weatherShapeLock ?? ""

    optionsComponent: Component {
        ShapePicker {
            selected: root.shapeLock
            autoHint: "Follows the weather, ghost at night"
            onPicked: name => SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { weatherShapeLock: name })
        }
    }

    readonly property bool metric: SettingsConfig.weather.useMetric ?? true
    readonly property int code: parseInt(ServiceWeather.weatherCode, 10) || 113
    readonly property bool night: {
        ServiceClock.minute
        return ServiceWeather.isNightTime()
    }

    readonly property var snowCodes: [179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332,
                                      335, 338, 350, 362, 365, 368, 371, 374, 377]

    readonly property string kind: {
        const c = root.code
        if (c === 113) return root.night ? "night" : "clear"
        if (c === 116) return "partly"
        if (c === 119 || c === 122) return "cloudy"
        if (c === 143 || c === 248 || c === 260) return "fog"
        if (c === 200 || c >= 386) return "storm"
        if (root.snowCodes.indexOf(c) >= 0) return "snow"
        return "rain"
    }

    shape: {
        if (root.shapeLock !== "") return ShapeLibrary.get(root.shapeLock) ?? MaterialShapeFn.getCircle()
        switch (root.kind) {
        case "clear":  return MaterialShapeFn.getSunny()
        case "night":  return MaterialShapeFn.getGhostish()
        case "partly": return MaterialShapeFn.getFlower()
        case "cloudy": return MaterialShapeFn.getPuffy()
        case "fog":    return MaterialShapeFn.getPuffyDiamond()
        case "snow":   return MaterialShapeFn.getClover8Leaf()
        case "storm":  return MaterialShapeFn.getSoftBoom()
        default:       return MaterialShapeFn.getBun()
        }
    }

    readonly property var today: ServiceWeather.forecastDays?.[0] ?? null

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        CustomText {
            Layout.alignment: Qt.AlignHCenter
            content: ServiceWeather.temperature
            size: Math.round(root.faceSize * 0.25)
            weight: 400
            customColor: Colors.primary
            font.family: SettingsConfig.general.displayFont ?? "Titan One"
            renderType: Text.QtRendering
        }

        CustomText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.faceSize * 0.6
            content: ServiceWeather.description
            size: 12
            customColor: Colors.surfaceText
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        CustomText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            visible: root.today !== null
            content: root.today
                ? (root.metric ? root.today.maxtempC : root.today.maxtempF) + "° / "
                  + (root.metric ? root.today.mintempC : root.today.mintempF) + "°"
                : ""
            size: 11
            customColor: Colors.outline
        }
    }
}
