import QtQuick
import "./services" as Services

// Clock card — control-center-style two-column panel. The pill morphs to
// modes.clock (620x520) and this centers inside it.
//   left  : month calendar (nav + crossfade), animated weather strip
//           (bobbing glyph, counting temp, kind-driven particle canvas),
//           pomodoro card (smooth progress ring)
//   right : the task list — a real scrolling surface. The old card used
//           a fixed 120px ListView inside a fixed 520px Column, so tasks
//           past the fold were cropped off; this list flexes to the card,
//           scrolls, animates inserts, and snaps to the end when a task
//           is added so it can never land outside the viewport.
Rectangle {
    id: root
    width: 620
    height: 520
    radius: 18
    color: Services.Colors.background

    // Refreshes once a minute so "today" in the calendar and the date
    // string stay correct across midnight without needing a shell restart.
    property var now: new Date()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // Focus helpers — called from Bar.qml's ClockCard Connections. The
    // card opens with taskInput already focused (launcher search recipe:
    // the bar is Exclusive while the card is open, so keys flow straight
    // into the field), and closing it drops any half-typed task the same
    // way the launcher drops its query.
    function focusTaskInput() { taskInput.forceActiveFocus() }
    function clearTaskInput() { taskInput.text = "" }

    readonly property int todayDate: now.getDate()
    readonly property int todayMonth: now.getMonth()
    readonly property int todayYear: now.getFullYear()

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ---------------- header: clock + date (+ live pomodoro chip) ----------------
        Item {
            width: parent.width
            height: 40

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    font.family: Services.Fonts.family
                    anchors.verticalCenter: parent.verticalCenter
                    text: Services.Time.time
                    font.pixelSize: 28
                    font.weight: Font.Light
                    color: Services.Colors.text
                }
                Text {
                    font.family: Services.Fonts.family
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.now.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
                    font.pixelSize: 12
                    color: Services.Colors.textMuted
                }
            }

            Rectangle {
                visible: Services.Pomodoro.running || Services.Pomodoro.phase !== "work"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: pomChipRow.implicitWidth + 18
                height: 24
                radius: 12
                color: Services.Colors.surface
                border.width: 1
                border.color: Services.Colors.low

                Row {
                    id: pomChipRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 7; radius: 4
                        color: Services.Colors.accent
                        opacity: Services.Pomodoro.running ? 1 : 0.45
                        Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast } }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        text: Services.Pomodoro.phaseLabel
                        font.pixelSize: 10
                        font.bold: true
                        color: Services.Colors.accent
                    }
                    Text {
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        text: Services.Pomodoro.display
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Colors.text
                    }
                }
            }
        }

        // ---------------- body ----------------
        Row {
            width: parent.width
            height: parent.height - 50
            spacing: 12

            // ============ LEFT: calendar + weather + pomodoro ============
            Column {
                width: 348
                height: parent.height
                spacing: 12

                // ---------------- calendar ----------------
                Rectangle {
                    width: parent.width
                    height: 236
                    radius: 12
                    color: Services.Colors.surface
                    border.width: 1
                    border.color: Services.Colors.low

                    // Crossfade on month change: fade out, swap the month in
                    // the timer, fade back in. No opacity binding here on
                    // purpose — the nav function assigns it imperatively.
                    Item {
                        id: calBody
                        anchors.fill: parent
                        anchors.margins: 12

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Services.Motion.effectsFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }

                        function nav(dir) {
                            opacity = 0
                            navTimer.dir = dir
                            navTimer.restart()
                        }

                        Timer {
                            id: navTimer
                            property int dir: 1
                            interval: Services.Motion.effectsFast
                            onTriggered: {
                                cal.monthOffset += dir
                                calBody.opacity = 1
                            }
                        }

                        Column {
                            id: cal
                            width: parent.width
                            spacing: 6

                            property int monthOffset: 0
                            readonly property date firstOfMonth:
                                new Date(root.todayYear, root.todayMonth + monthOffset, 1)
                            readonly property int firstWeekday:
                                (firstOfMonth.getDay() + 6) % 7   // Monday-first
                            readonly property int daysInMonth:
                                new Date(firstOfMonth.getFullYear(), firstOfMonth.getMonth() + 1, 0).getDate()
                            readonly property string monthLabel:
                                firstOfMonth.toLocaleDateString(Qt.locale(), "MMMM yyyy")

                            // nav row: ‹ month › ... Today chip when off-month
                            Item {
                                width: parent.width
                                height: 24

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        color: prevMa.containsMouse
                                            ? Services.Colors.surfaceAlt : "transparent"
                                        Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast } }
                                        Text {
                                            font.family: Services.Fonts.family
                                            anchors.centerIn: parent
                                            text: "‹"
                                            font.pixelSize: 15
                                            color: Services.Colors.textMuted
                                        }
                                        MouseArea {
                                            id: prevMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: calBody.nav(-1)
                                        }
                                    }

                                    Text {
                                        font.family: Services.Fonts.family
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cal.monthLabel
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: Services.Colors.text
                                    }

                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        color: nextMa.containsMouse
                                            ? Services.Colors.surfaceAlt : "transparent"
                                        Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast } }
                                        Text {
                                            font.family: Services.Fonts.family
                                            anchors.centerIn: parent
                                            text: "›"
                                            font.pixelSize: 15
                                            color: Services.Colors.textMuted
                                        }
                                        MouseArea {
                                            id: nextMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: calBody.nav(1)
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: cal.monthOffset !== 0
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: todayTxt.implicitWidth + 16
                                    height: 22
                                    radius: 11
                                    color: Services.Colors.surfaceAlt
                                    Text {
                                        font.family: Services.Fonts.family
                                        id: todayTxt
                                        anchors.centerIn: parent
                                        text: "Today"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Services.Colors.accent
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: calBody.nav(-cal.monthOffset)
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                Repeater {
                                    model: ["M", "T", "W", "T", "F", "S", "S"]
                                    delegate: Text {
                                        font.family: Services.Fonts.family
                                        width: cal.width / 7
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        font.pixelSize: 10
                                        color: Services.Colors.textMuted
                                    }
                                }
                            }

                            Grid {
                                width: parent.width
                                columns: 7

                                Repeater {
                                    model: cal.firstWeekday
                                    delegate: Item {
                                        width: cal.width / 7
                                        height: 26
                                    }
                                }
                                Repeater {
                                    model: cal.daysInMonth
                                    delegate: Item {
                                        width: cal.width / 7
                                        height: 26
                                        readonly property int dayNum: index + 1
                                        readonly property bool isToday:
                                            cal.monthOffset === 0 && dayNum === root.todayDate

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 22; height: 22; radius: 11
                                            color: isToday ? Services.Colors.accent : "transparent"
                                        }
                                        Text {
                                            font.family: Services.Fonts.family
                                            anchors.centerIn: parent
                                            text: dayNum
                                            font.pixelSize: 11
                                            color: isToday ? Services.Colors.background
                                                           : Services.Colors.text
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------------- animated weather strip ----------------
                Rectangle {
                    width: parent.width
                    height: 76
                    radius: 12
                    color: Services.Colors.surface
                    border.width: 1
                    border.color: Services.Colors.low

                    // bobbing glyph
                    Item {
                        id: glyphBox
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 44

                        Text {
                            font.family: Services.Fonts.family
                            id: wxGlyph
                            x: 0
                            y: 8
                            text: Services.Weather.glyph
                            // explicit colour again — with no color: this
                            // glyph fell back to QML's default black and
                            // ignored the theme, exactly like the pomodoro icon.
                            color: Services.Colors.text
                            font.pixelSize: 26

                            SequentialAnimation on y {
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 5
                                    duration: Services.Motion.emphasizedEnter
                                    easing.type: Easing.InOutSine
                                }
                                PauseAnimation { duration: 300 }
                                NumberAnimation {
                                    to: 8
                                    duration: Services.Motion.emphasizedEnter
                                    easing.type: Easing.InOutSine
                                }
                                PauseAnimation { duration: 1200 }
                            }
                        }
                    }

                    // temp (counts to the new value on refresh) + condition
                    Column {
                        anchors.left: glyphBox.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            font.family: Services.Fonts.family
                            id: tempTxt
                            property real shown: Services.Weather.tempNum
                            Behavior on shown {
                                NumberAnimation {
                                    duration: Services.Motion.medium3
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.standardDecelerate
                                }
                            }
                            text: Services.Weather.ok ? Math.round(shown) + "°" : "—"
                            font.pixelSize: 22
                            font.bold: true
                            color: Services.Colors.text
                        }
                        Text {
                            font.family: Services.Fonts.family
                            width: 150
                            elide: Text.ElideRight
                            text: Services.Weather.ok ? Services.Weather.desc.trim() : "Loading…"
                            font.pixelSize: 10
                            color: Services.Colors.textMuted
                        }
                    }

                    // kind-driven particle canvas: rain/snow/fog/sun/cloud
                    Canvas {
                        id: wxCanvas
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 108
                        height: 52

                        property real t: 0
                        property string kind: Services.Weather.kind

                        onKindChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

                        onPaint: {
                            const ctx = getContext("2d")
                            const w = width, h = height
                            ctx.clearRect(0, 0, w, h)
                            const time = t
                            const k = kind
                            const muted = Services.Colors.textMuted
                            const acc = Services.Colors.accent

                            if (k === "rain" || k === "thunder") {
                                if (k === "thunder" && (time % 3) < 0.25) {
                                    ctx.fillStyle = rgba(acc, 0.10)
                                    ctx.fillRect(0, 0, w, h)
                                }
                                ctx.strokeStyle = rgba(muted, 0.8)
                                ctx.lineWidth = 1.4
                                for (let i = 0; i < 14; i++) {
                                    const speed = 55 + (i % 5) * 14
                                    const y = ((i * 13 + time * speed) % (h + 12)) - 12
                                    const x = (i * 17 + y * 0.3) % w
                                    ctx.beginPath()
                                    ctx.moveTo(x, y)
                                    ctx.lineTo(x - 2.5, y + 8)
                                    ctx.stroke()
                                }
                            } else if (k === "snow") {
                                ctx.fillStyle = rgba(muted, 0.85)
                                for (let i = 0; i < 12; i++) {
                                    const y = ((i * 17 + time * (16 + (i % 4) * 6)) % (h + 8)) - 4
                                    const x = (((i * 23) % w) + Math.sin(time * 1.6 + i) * 6 + w) % w
                                    ctx.beginPath()
                                    ctx.arc(x, y, 1.6 + (i % 3) * 0.5, 0, Math.PI * 2)
                                    ctx.fill()
                                }
                            } else if (k === "fog") {
                                ctx.fillStyle = rgba(muted, 0.30)
                                for (let i = 0; i < 3; i++) {
                                    const bw = 54
                                    let x = (i * 41 - time * 14) % (bw + w)
                                    if (x < 0) x += bw + w
                                    ctx.fillRect(x - bw, 8 + i * 14, bw, 6)
                                }
                            } else if (k === "sun") {
                                const cx = w / 2, cy = h / 2
                                const pulse = 0.5 + 0.5 * Math.sin(time * 2.2)
                                const r = 16 + pulse * 5
                                const g = ctx.createRadialGradient(cx, cy, 2, cx, cy, r + 8)
                                g.addColorStop(0, rgba(acc, 0.35 + pulse * 0.2))
                                g.addColorStop(1, rgba(acc, 0))
                                ctx.fillStyle = g
                                ctx.beginPath()
                                ctx.arc(cx, cy, r + 8, 0, Math.PI * 2)
                                ctx.fill()
                            } else { // cloud / partly — drifting soft ellipses
                                ctx.fillStyle = rgba(muted, 0.28)
                                for (let i = 0; i < 3; i++) {
                                    const bw = 34 + i * 8
                                    let x = (i * 44 - time * (7 + i * 3)) % (bw + w)
                                    if (x < 0) x += bw + w
                                    ctx.beginPath()
                                    ctx.ellipse(x - bw, 14 + i * 12, bw, 7 + i, 0, 0, Math.PI * 2)
                                    ctx.fill()
                                }
                            }
                        }

                        Timer {
                            interval: 66
                            running: Services.ClockCard.open
                            repeat: true
                            onTriggered: { wxCanvas.t += 0.066; wxCanvas.requestPaint() }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Weather.refresh()
                    }
                }

                // ---------------- pomodoro ----------------
                Rectangle {
                    width: parent.width
                    height: 106
                    radius: 12
                    color: Services.Colors.surface
                    border.width: 1
                    border.color: Services.Colors.low

                    // progress ring — Behavior smooths the 1s ticks into a
                    // continuous sweep
                    Item {
                        id: ringBox
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        height: 64

                        Canvas {
                            id: pomRing
                            anchors.fill: parent

                            property real frac: Services.Pomodoro.progress
                            Behavior on frac {
                                NumberAnimation { duration: 1000; easing.type: Easing.Linear }
                            }
                            onFracChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d")
                                const w = width, h = height, cx = w / 2, cy = h / 2, r = w / 2 - 5
                                ctx.clearRect(0, 0, w, h)

                                ctx.beginPath()
                                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                ctx.strokeStyle = Services.Colors.low
                                ctx.lineWidth = 5
                                ctx.stroke()

                                const f = Math.max(0, Math.min(1, frac))
                                const start = -Math.PI / 2
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, start, start + f * Math.PI * 2)
                                ctx.strokeStyle = Services.Colors.accent
                                ctx.lineWidth = 5
                                ctx.lineCap = "round"
                                ctx.stroke()
                            }
                        }

                        // nerd icons only — fa-bullseye (focus),
                        // fa-coffee (short break), md-weather-night
                        // (long break). The old emoji trio 🍅☕🌙 is gone.
                        Text {
                            font.family: Services.Fonts.family
                            anchors.centerIn: parent
                            text: Services.Pomodoro.phase === "work" ? ""
                                : Services.Pomodoro.phase === "break" ? ""
                                : "󰖔"
                            // colour is EXPLICIT and required: a bare Text
                            // with no color: inherits QML's default of black,
                            // which is why this glyph rendered solid black and
                            // ignored the theme entirely. Services.Colors.text
                            // is the same value the clock uses
                            // (modules/Clock.qml -> Colors.text), so the icon
                            // now tracks the theme like everything around it.
                            color: Services.Colors.text
                            font.pixelSize: 18
                        }
                    }

                    Column {
                        anchors.left: ringBox.right
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // phase + cycle dots
                        Item {
                            width: parent.width
                            height: 14
                            readonly property int filled:
                                Services.Pomodoro.phase === "longBreak"
                                    ? Services.Pomodoro.cyclesBeforeLongBreak
                                    : Services.Pomodoro.completedCycles
                                        % Services.Pomodoro.cyclesBeforeLongBreak

                            Text {
                                font.family: Services.Fonts.family
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: Services.Pomodoro.phaseLabel
                                font.pixelSize: 10
                                font.bold: true
                                color: Services.Colors.accent
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Repeater {
                                    model: Services.Pomodoro.cyclesBeforeLongBreak
                                    delegate: Rectangle {
                                        required property int index
                                        width: 6; height: 6; radius: 3
                                        color: index < parent.parent.filled
                                            ? Services.Colors.accent : Services.Colors.low
                                    }
                                }
                            }
                        }

                        Text {
                            font.family: Services.Fonts.family
                            text: Services.Pomodoro.display
                            font.pixelSize: 26
                            font.weight: Font.Light
                            color: Services.Colors.text
                        }

                        Row {
                            spacing: 8

                            Rectangle {
                                width: 74; height: 28; radius: 14
                                color: Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g,
                                              Services.Colors.accent.b, 0.18)
                                scale: startMa.pressed ? 0.94 : 1
                                Behavior on scale {
                                    SpringAnimation {
                                        spring: Services.Motion.popSpring
                                        damping: Services.Motion.popDamping
                                    }
                                }
                                Text {
                                    font.family: Services.Fonts.family
                                    anchors.centerIn: parent
                                    text: Services.Pomodoro.running ? "Pause" : "Start"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Services.Colors.accent
                                }
                                MouseArea {
                                    id: startMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.Pomodoro.running
                                        ? Services.Pomodoro.pause() : Services.Pomodoro.start()
                                }
                            }

                            Rectangle {
                                width: 52; height: 28; radius: 14
                                color: Services.Colors.surfaceAlt
                                scale: skipMa.pressed ? 0.94 : 1
                                Behavior on scale {
                                    SpringAnimation {
                                        spring: Services.Motion.popSpring
                                        damping: Services.Motion.popDamping
                                    }
                                }
                                Text {
                                    font.family: Services.Fonts.family
                                    anchors.centerIn: parent
                                    text: "Skip"
                                    font.pixelSize: 12
                                    color: Services.Colors.text
                                }
                                MouseArea {
                                    id: skipMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.Pomodoro.skip()
                                }
                            }

                            Rectangle {
                                width: 56; height: 28; radius: 14
                                color: Services.Colors.surfaceAlt
                                scale: resetMa.pressed ? 0.94 : 1
                                Behavior on scale {
                                    SpringAnimation {
                                        spring: Services.Motion.popSpring
                                        damping: Services.Motion.popDamping
                                    }
                                }
                                Text {
                                    font.family: Services.Fonts.family
                                    anchors.centerIn: parent
                                    text: "Reset"
                                    font.pixelSize: 12
                                    color: Services.Colors.text
                                }
                                MouseArea {
                                    id: resetMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.Pomodoro.reset()
                                }
                            }
                        }
                    }
                }
            }

            // ============ RIGHT: task list ============
            Rectangle {
                id: tasksCard
                width: 232
                height: parent.height
                radius: 12
                color: Services.Colors.surface
                border.width: 1
                border.color: Services.Colors.low

                readonly property int doneCount:
                    Services.Tasks.items.filter(t => t.done).length

                Column {
                    id: tasksHead
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 18

                        Text {
                            font.family: Services.Fonts.family
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Tasks"
                            font.pixelSize: 13
                            font.bold: true
                            color: Services.Colors.text
                        }

                        Rectangle {
                            visible: Services.Tasks.items.length > 0
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: countTxt.implicitWidth + 14
                            height: 18
                            radius: 9
                            color: Services.Colors.surfaceAlt
                            Text {
                                font.family: Services.Fonts.family
                                id: countTxt
                                anchors.centerIn: parent
                                text: tasksCard.doneCount + "/" + Services.Tasks.items.length
                                font.pixelSize: 9
                                font.bold: true
                                color: Services.Colors.textMuted
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 30
                        radius: 8
                        color: Services.Colors.surfaceAlt
                        border.width: 1
                        border.color: taskInput.activeFocus
                            ? Services.Colors.accent : "transparent"
                        Behavior on border.color { ColorAnimation { duration: Services.Motion.effectsFast } }

                        TextInput {
                            font.family: Services.Fonts.family
                            id: taskInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            verticalAlignment: TextInput.AlignVCenter
                            onAccepted: {
                                Services.Tasks.addTask(text)
                                text = ""
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Add a task…"
                                font.pixelSize: 12
                                color: Services.Colors.textMuted
                                opacity: taskInput.text === "" ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast } }
                            }
                        }
                    }
                }

                // The scrolling surface — flexes with the card (the old
                // fixed 120px list is what cropped tasks off).
                ListView {
                    id: taskList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: tasksHead.bottom
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10   // room for the scrollbar thumb
                    anchors.topMargin: 10
                    anchors.bottomMargin: 14
                    clip: true
                    spacing: 4
                    model: Services.Tasks.items

                    // Adding a task while scrolled up must never hide it:
                    // snap to the end on growth.
                    property int prevCount: Services.Tasks.items.length
                    Connections {
                        target: Services.Tasks
                        function onItemsChanged() {
                            if (Services.Tasks.items.length > taskList.prevCount)
                                taskList.positionViewAtEnd()
                            taskList.prevCount = Services.Tasks.items.length
                        }
                    }

                    add: Transition {
                        NumberAnimation {
                            properties: "opacity"
                            from: 0
                            duration: Services.Motion.effectsFast
                        }
                        NumberAnimation {
                            properties: "x"
                            from: 24
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                    displaced: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    delegate: Rectangle {
                        id: del
                        required property var modelData

                        width: taskList.width
                        height: 30
                        radius: 8
                        color: hovMa.containsMouse ? Services.Colors.background : "transparent"
                        Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast } }

                        Rectangle {
                            id: box
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 5
                            color: modelData.done ? Services.Colors.accent : "transparent"
                            border.width: 1.5
                            border.color: modelData.done ? Services.Colors.accent
                                : (hovMa.containsMouse ? Services.Colors.accent : Services.Colors.textMuted)
                            Behavior on border.color { ColorAnimation { duration: Services.Motion.effectsFast } }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.centerIn: parent
                                visible: modelData.done
                                text: "✓"
                                font.pixelSize: 10
                                font.bold: true
                                color: Services.Colors.background
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Tasks.toggleTask(modelData.id)
                            }
                        }

                        Text {
                            font.family: Services.Fonts.family
                            anchors.left: box.right
                            anchors.leftMargin: 8
                            anchors.right: delX.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            font.pixelSize: 12
                            font.strikeout: modelData.done
                            elide: Text.ElideRight
                            color: modelData.done ? Services.Colors.textMuted : Services.Colors.text
                            Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast } }
                        }

                        Rectangle {
                            id: delX
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 9
                            color: delMa.containsMouse
                                ? Qt.rgba(Services.Colors.critical.r, Services.Colors.critical.g,
                                          Services.Colors.critical.b, 0.22)
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast } }
                            opacity: hovMa.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast } }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 9
                                color: Services.Colors.critical
                            }
                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Tasks.removeTask(modelData.id)
                            }
                        }

                        // hover detector, declared last so it sits on top;
                        // NoButton lets the checkbox/delete areas still take
                        // the clicks.
                        MouseArea {
                            id: hovMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }

                // scrollbar thumb (settings-sidebar pattern)
                Rectangle {
                    visible: taskList.contentHeight > taskList.height + 1
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    y: taskList.y + taskList.contentY * (taskList.height / taskList.contentHeight)
                    height: Math.max(20, taskList.height * (taskList.height / taskList.contentHeight))
                    width: 3
                    radius: 1.5
                    opacity: 0.5
                    color: Services.Colors.textMuted
                }

                Text {
                    font.family: Services.Fonts.family
                    visible: Services.Tasks.items.length === 0
                    anchors.centerIn: taskList
                    text: "Nothing yet — add one above"
                    font.pixelSize: 11
                    color: Services.Colors.textMuted
                }
            }
        }
    }
}
