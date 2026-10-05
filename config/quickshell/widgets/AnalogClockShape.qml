// Ported from Nebula's Widgets/AnalogClockShape.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "shapes/" as MaterialShapes
import "shapes/material-shapes.js" as MaterialShapeFn
import "shapes/shape-library.js" as ShapeLibrary

WidgetHost {
    id: root
    configKey: "analogClock"
    tile: WidgetSizes.small
    defaultPos: Qt.point(400, 200)
    backdropMask: shapeMask

    property real clockSize: WidgetSizes.small.width

    readonly property string shapeLock: SettingsConfig.widgets.analogShapeLock ?? ""
    readonly property var faceShape: root.shapeLock !== ""
        ? (ShapeLibrary.get(root.shapeLock) ?? MaterialShapeFn.getCookie12Sided())
        : MaterialShapeFn.getCookie12Sided()

    optionsComponent: Component {
        ShapePicker {
            selected: root.shapeLock
            autoHint: "The classic 12-sided cookie"
            onPicked: name => SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { analogShapeLock: name })
        }
    }

    MaterialShapes.ShapeCanvas {
        anchors.centerIn: parent
        width: root.clockSize
        height: root.clockSize
        roundedPolygon: root.faceShape
        color: WidgetSizes.cardColor
    }

    // Hour hand
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.verticalCenter
        width: 10
        height: root.clockSize * 0.24
        radius: 5
        color: "transparent"//Colors.surfaceText
        border.width: 2
        border.color: Colors.primary
        transformOrigin: Item.Bottom
        rotation: (parseInt(ServiceClock.hour) % 12 + parseInt(ServiceClock.minute) / 60) / 12 * 360
        Behavior on rotation {
            RotationAnimation { direction: RotationAnimation.Clockwise; duration: 400; easing.type: Easing.OutCubic }
        }
    }

    // Minute hand
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.verticalCenter
        width: 6
        height: root.clockSize * 0.32
        radius: 3
        color: Colors.surfaceText
        transformOrigin: Item.Bottom
        rotation: (parseInt(ServiceClock.minute) + parseInt(ServiceClock.seconds) / 60) / 60 * 360
    }

    // Second hand
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.verticalCenter
        width: 2
        height: root.clockSize * 0.35
        radius: 1
        color: Colors.primary
        transformOrigin: Item.Bottom
        rotation: parseInt(ServiceClock.seconds) / 60 * 360
        Behavior on rotation {
            RotationAnimation { direction: RotationAnimation.Clockwise; duration: 200; easing.type: Easing.Linear }
        }
    }

    // Center cap
    Rectangle {
        anchors.centerIn: parent
        width: 14; height: 14; radius: 7
        color: Colors.primary
        z: 10
    }
    Rectangle {
        anchors.centerIn: parent
        width: 6; height: 6; radius: 3
        color: Colors.primaryText
        z: 11
    }
    Item {
        id: maskSource
        anchors.fill: parent

        MaterialShapes.ShapeCanvas {
            anchors.centerIn: parent
            width: root.clockSize
            height: root.clockSize
            roundedPolygon: root.faceShape
            color: "white"
        }
    }

    Item {
        width: 0
        height: 0
        clip: true

        ShaderEffectSource {
            id: shapeMask
            width: root.width
            height: root.height
            textureSize: Qt.size(root.width, root.height)
            sourceItem: maskSource
            hideSource: true
            live: true
        }
    }
}
