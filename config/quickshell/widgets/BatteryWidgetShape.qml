// Ported from Nebula's Widgets/BatteryWidgetShape.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "shapes/" as MaterialShapes
import "shapes/material-shapes.js" as MaterialShapeFn
import "shapes/shape-library.js" as ShapeLibrary

ShapeWidget {
    id: root
    configKey: "battery"
    tile: WidgetSizes.small
    defaultPos: Qt.point(600, 200)

    readonly property string shapeLock: SettingsConfig.widgets.batteryShapeLock ?? ""

    optionsComponent: Component {
        ShapePicker {
            selected: root.shapeLock
            autoHint: "Spins while charging, turns ghostly when low"
            onPicked: name => SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { batteryShapeLock: name })
        }
    }

    readonly property real pct: Math.max(0, Math.min(1, ServiceUPower.powerLevel))
    readonly property bool charging: ServiceUPower.isCharging
    readonly property bool low: root.pct < 0.15 && !root.charging

    readonly property real faceTop: (root.height - root.faceSize) / 2

    shape: root.shapeLock !== "" ? (ShapeLibrary.get(root.shapeLock) ?? MaterialShapeFn.getCircle())
         : root.charging ? MaterialShapeFn.getVerySunny()
         : root.low      ? MaterialShapeFn.getGhostish()
                         : MaterialShapeFn.getCookie9Sided()

    onChargingChanged: if (!root.charging) root.faceRotation = 0

    NumberAnimation on faceRotation {
        running: root.charging && !root.preview
        from: 0
        to: 360
        duration: 14000
        loops: Animation.Infinite
    }

    CustomText {
        id: pctBase
        anchors.centerIn: parent
        content: Math.round(root.pct * 100) + "%"
        size: Math.round(root.faceSize * 0.2)
        weight: 400
        customColor: root.low ? Colors.error : Colors.surfaceText
        font.family: SettingsConfig.general.displayFont ?? "Titan One"
        renderType: Text.QtRendering
    }

    Item {
        id: fillClip
        x: 0
        width: root.width
        height: root.faceSize * root.pct
        y: root.faceTop + root.faceSize - height
        clip: true

        Behavior on height { SpatialAnim { speed: "slow" } }

        MaterialShapes.ShapeCanvas {
            x: (root.width - root.faceSize) / 2
            y: root.faceTop - fillClip.y
            width: root.faceSize
            height: root.faceSize
            rotation: root.faceRotation
            roundedPolygon: root.shape
            color: Colors.primary
        }

        CustomText {
            x: pctBase.x
            y: pctBase.y - fillClip.y
            content: pctBase.content
            size: pctBase.size
            weight: 400
            customColor: Colors.primaryText
            font.family: pctBase.font.family
            renderType: Text.QtRendering
        }
    }
}
