import QtQuick
import "../services" as Services

// In-bar media trigger: a small animated equaliser sitting in the pill's
// rest row just before the clock (compact capsule AND wide segmented
// row). Click morphs the pill itself into the media card
// (Services.Media.open -> pill.mode "media") — this replaces the old
// activity chip + detached mediaPopup, the piece that kept media "inside
// the bar". Hidden entirely while no player exists; ~47px wide so it's a
// comfortable click target.
//
// The bars follow playback STATE only — feet planted on the bottom
// baseline, growing UP toward the top (accent + bouncing while playing,
// flat + muted when paused). No position ticking anywhere: the old 1s
// position timer died with the progress UI.
Rectangle {
    id: vis

    readonly property bool playing: Services.Media.playing

    height: 26
    radius: 13
    color: Services.Colors.surface
    anchors.verticalCenter: parent.verticalCenter
    // hidden players leave the Row entirely (visible:false children are
    // skipped by positioners), so the capsule doesn't keep their spacing
    width: Services.Media.hasPlayer ? barsRow.implicitWidth + 16 : 0
    opacity: Services.Media.hasPlayer ? 1 : 0
    visible: opacity > 0.01
    clip: true

    Behavior on width { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }
    Behavior on opacity { NumberAnimation { duration: Services.Motion.medium1; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }
    Behavior on color { ColorAnimation { duration: 150 } }

    Row {
        id: barsRow
        anchors.centerIn: parent
        spacing: 4
        // pinned at the tallest possible bar so the baseline never shifts
        // while the bars animate — this edge is the floor the feet sit on
        height: 16

        Repeater {
            model: 5

            delegate: Rectangle {
                id: bar
                required property int index

                // The SequentialAnimation drives targetH; height only
                // BINDS off it (playing ? targetH : 8), so stopping
                // playback snaps every bar back to the resting height
                // without needing to poke the animation's stop state.
                property real targetH: 8
                readonly property int phase: (index * 137) % 700
                readonly property int rise: 380 + ((index * 91) % 260)
                readonly property int fall: 340 + ((index * 53) % 240)

                width: 3
                radius: 1.5
                height: vis.playing ? targetH : 8
                // base DOWN: pin the bottom edge to the row floor so a
                // height change moves the top (bars reach upward).
                // Positioners only lay out their main axis, so y stays
                // ours to bind.
                y: barsRow.height - height
                color: vis.playing ? Services.Colors.accent : Services.Colors.textMuted

                SequentialAnimation {
                    loops: Animation.Infinite
                    running: vis.playing

                    PauseAnimation { duration: bar.phase }
                    NumberAnimation {
                        target: bar
                        property: "targetH"
                        to: 16
                        duration: bar.rise
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: bar
                        property: "targetH"
                        to: 5
                        duration: bar.fall
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Services.Media.toggle()
    }
}
