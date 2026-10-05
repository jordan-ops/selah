// Ported from Nebula's Widgets/DateWidgetShape.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "shapes/material-shapes.js" as MaterialShapeFn
import "shapes/shape-library.js" as ShapeLibrary

ShapeWidget {
    id: root
    configKey: "dateWidget"
    tile: WidgetSizes.small
    defaultPos: Qt.point(300, 300)

    readonly property string shapeLock: SettingsConfig.widgets.dateShapeLock ?? ""

    optionsComponent: Component {
        ShapePicker {
            selected: root.shapeLock
            autoHint: "A different shape for each weekday"
            onPicked: name => SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { dateShapeLock: name })
        }
    }

    shape: {
        if (root.shapeLock !== "") return ShapeLibrary.get(root.shapeLock) ?? MaterialShapeFn.getCircle()
        switch (ServiceClock.day) {
        case "Tuesday":   return MaterialShapeFn.getClover4Leaf()
        case "Wednesday": return MaterialShapeFn.getSunny()
        case "Thursday":  return MaterialShapeFn.getPentagon()
        case "Friday":    return MaterialShapeFn.getFlower()
        case "Saturday":  return MaterialShapeFn.getCookie9Sided()
        case "Sunday":    return MaterialShapeFn.getVerySunny()
        default:          return MaterialShapeFn.getCookie7Sided()
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: -4

        CustomText {
            Layout.alignment: Qt.AlignHCenter
            content: ServiceClock.date
            size: Math.round(root.faceSize * 0.33)
            weight: 400
            customColor: Colors.primary
            font.family: SettingsConfig.general.displayFont ?? "Titan One"
            renderType: Text.QtRendering
        }

        CustomText {
            Layout.alignment: Qt.AlignHCenter
            content: String(ServiceClock.day).slice(0, 3).toUpperCase()
                   + " · " + String(ServiceClock.month).slice(0, 3).toUpperCase()
            size: 11
            weight: 700
            customColor: Colors.outline
            font.letterSpacing: 2
        }
    }
}
