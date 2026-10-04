import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Widgets
import QtQuick
import "./services" as Services

PanelWindow {
    anchors { top: true; right: true }
    implicitWidth: 320
    implicitHeight: notifColumn.height
    margins.right: 12
    margins.top: 60
    color: "transparent"

    // window height follows the column's real height, animated —
    // same idea as the pill morph: content decides size, window follows it.
    Behavior on implicitHeight { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Column {
        id: notifColumn
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: 8

        // smoothly slides remaining cards up when one above them is removed
        move: Transition {
            SpringAnimation { properties: "y"; spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping }
        }

        Repeater {
            model: Services.Notifications.list

            Rectangle {
                id: card
                width: 300
                radius: 12
                color: Services.Colors.background
                height: content.height + 24
                opacity: 0
                x: 40
                clip: true   // contains overflow (e.g. long unbroken URLs) inside the rounded corners

                Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                property bool pendingExpire: false

                // hover holds the auto-close: the remaining time banks on
                // enter and the clock resumes with it on leave, so reading
                // a long card never races the timer
                property real expireTotal: modelData.expireTimeout > 0 ? modelData.expireTimeout * 1000 : 5000
                property real expireLeft: expireTotal
                property real expireT0: Date.now()

                property color accent: {
                    if (modelData.urgency === NotificationUrgency.Critical) return Services.Colors.critical
                    if (modelData.urgency === NotificationUrgency.Low) return Services.Colors.low
                    return Services.Colors.accent
                }

                function closeCard(expire) {
                    pendingExpire = expire
                    exitAnim.start()
                }

                Component.onCompleted: enterAnim.start()

                ParallelAnimation {
                    id: enterAnim
                    // M3E enter: the fade keeps emphasized decelerate @400ms,
                    // the x slide rides the bounce spring (spatial = springs)
                    NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Services.Motion.emphasizedEnter; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate }
                    SpringAnimation { target: card; property: "x"; from: 40; to: 0; spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping }
                }

                ParallelAnimation {
                    id: exitAnim
                    // M3 emphasized exit: accelerate curve @ 200ms
                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: Services.Motion.emphasizedExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedAccelerate }
                    NumberAnimation { target: card; property: "x"; to: 40; duration: Services.Motion.emphasizedExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedAccelerate }
                    onStopped: {
                        if (card.pendingExpire) modelData.expire()
                        else modelData.dismiss()
                    }
                }

                Rectangle {
                    width: 4
                    height: parent.height
                    radius: 2
                    color: card.accent
                }

                Row {
                    id: content
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 10

                    IconImage {
                        id: appIcon
                        implicitSize: 32
                        source: modelData.appIcon !== "" ? Quickshell.iconPath(modelData.appIcon, true) : ""
                    }

                    Column {
                        width: parent.width - appIcon.implicitSize - 10
                        spacing: 4

                        Text {
                            color: Services.Colors.text
                            font.bold: true
                            font.pixelSize: 13
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.summary
                        }

                        Text {
                            color: Services.Colors.accent
                            font.pixelSize: 12
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: modelData.body
                            // No line cap / elide: the card grows to fit the real
                            // message instead of chopping it with "...". Guard
                            // against a truly runaway body (e.g. a bad app spamming
                            // paragraphs) with a generous line ceiling instead.
                            maximumLineCount: 20
                            elide: Text.ElideRight
                        }
                    }
                }

                Timer {
                    id: expireTimer
                    interval: Math.max(500, card.expireLeft)
                    running: true
                    onTriggered: card.closeCard(true)
                }

                MouseArea {
                    anchors.fill: parent
                    // left dismisses (as always) and right-click dismisses
                    // too — every notification surface shares that gesture.
                    // Hover banks the auto-close clock: entering stops the
                    // timer at its remaining time, leaving resumes it.
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onEntered: {
                        if (!expireTimer.running) return
                        card.expireLeft = Math.max(500, expireTimer.interval - (Date.now() - card.expireT0))
                        expireTimer.stop()
                    }
                    onExited: {
                        card.expireT0 = Date.now()
                        expireTimer.restart()
                    }
                    onClicked: card.closeCard(false)
                }
            }
        }
    }
}
