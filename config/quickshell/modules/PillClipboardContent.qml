import QtQuick
import "../services" as Services

// Clipboard history panel — the launcher's shape (search row + list
// capped at 6 rows so the pill stays bounded), living in the pill's
// "clipboard" mode. Click a row: it copies and the panel closes (paste
// with Ctrl+V). Hover reveals a × that drops just that entry; "Clear"
// wipes the history. Search filters the stored one-line previews.
//
// Exposes listH — Bar's pill size thunk and this ListView both read it,
// so the pill height and the list can't drift apart (same contract as
// launcherListHeight).
Item {
    id: root
    property bool active: false
    anchors.fill: parent
    opacity: active ? 1 : 0
    // invisible != unclickable: without this the closed panel's
    // ListView stayed a live ~400x210 click-catcher hanging below
    // the 30px bar, stealing clicks from everything underneath.
    visible: active || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

    // 6 visible rows max; 40 = the empty-state line height (mirrors
    // launcherListHeight's fallback so both cases size the pill alike)
    readonly property int visibleRows: Math.min(Services.Clipboard.filtered.length, 6)
    readonly property real listH: visibleRows > 0
        ? visibleRows * 34 + (visibleRows - 1) * 2
        : 40

    // open -> focus the field, close -> drop the query (launcher pattern)
    onActiveChanged: {
        if (active) {
            searchField.forceActiveFocus()
            // the panel window only asks the compositor for keyboard focus on
            // the same frame Clipboard.open flips, so this first request can
            // land before focus is actually granted — and a surface without
            // focus silently swallows every key, which reads as "the search
            // box is dead". Re-assert once the compositor has settled.
            focusRetry.restart()
        } else {
            searchField.text = ""
        }
    }

    Timer {
        id: focusRetry
        interval: 80
        onTriggered: if (root.active) searchField.forceActiveFocus()
    }

    function relTime(ts) {
        const s = Math.max(0, Math.floor(Date.now() / 1000 - ts / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    function fmtSize(n) {
        if (n < 1024) return n + " B"
        if (n < 1024 * 1024) return Math.round(n / 1024) + " KB"
        return (n / (1024 * 1024)).toFixed(1) + " MB"
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Row {
            id: searchRow
            width: parent.width
            height: 30
            spacing: 8

            Text {
                font.family: Services.Fonts.family
                text: "󰍉"
                color: Services.Colors.text
                font.pixelSize: 15
                anchors.verticalCenter: parent.verticalCenter
            }

            TextInput {
                font.family: Services.Fonts.family
                id: searchField
                width: parent.width - 23 - (clearText.visible ? clearText.implicitWidth + 8 : 0)
                color: Services.Colors.text
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
                onTextChanged: Services.Clipboard.filter = text

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        if (text !== "") text = ""
                        else Services.Clipboard.close()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1)
                        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        list.currentIndex = Math.max(list.currentIndex - 1, 0)
                        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (list.count > 0) Services.Clipboard.copy(list.currentIndex)
                        event.accepted = true
                    }
                }
            }

            Text {
                font.family: Services.Fonts.family
                id: clearText
                visible: Services.Clipboard.entries.length > 0
                text: "Clear"
                color: clearArea.containsMouse ? Services.Colors.accent : Services.Colors.textMuted
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.Clipboard.clear()
                }
            }
        }

        Text {
            font.family: Services.Fonts.family
            visible: Services.Clipboard.filtered.length === 0
            width: parent.width
            height: 40
            verticalAlignment: Text.AlignVCenter
            color: Services.Colors.text
            opacity: 0.6
            font.pixelSize: 12
            text: Services.Clipboard.entries.length === 0
                ? "Clipboard is empty — copies show up here"
                : "No matches"
        }

        ListView {
            id: list
            width: parent.width
            height: root.listH
            visible: Services.Clipboard.filtered.length > 0
            clip: true
            spacing: 2
            model: Services.Clipboard.filtered
            // deletions shrink the model — keep currentIndex in range
            onCountChanged: {
                if (currentIndex >= count)
                    currentIndex = Math.max(0, count - 1)
            }

            delegate: Rectangle {
                id: row
                width: list.width
                height: 34
                radius: 8
                color: hot.containsMouse || del.containsMouse || ListView.isCurrentItem
                    ? Services.Colors.surface : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                readonly property bool isImage: modelData.mime.indexOf("image/") === 0
                readonly property string mainText: {
                    if (row.isImage)
                        return modelData.ext.toUpperCase() + " · " + root.fmtSize(modelData.size)
                    if (modelData.preview !== "")
                        return modelData.preview
                    return modelData.mime.split(";")[0] + " · " + root.fmtSize(modelData.size)
                }

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Image {
                        visible: row.isImage
                        width: visible ? 22 : 0
                        height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                        source: row.isImage ? "file://" + modelData.path : ""
                    }

                    Text {
                        font.family: Services.Fonts.family
                        width: parent.width
                            - (row.isImage ? 22 : 0)
                            - 30 - 14
                            - 8 * (row.isImage ? 3 : 2)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.mainText
                        color: Services.Colors.text
                        font.pixelSize: 12
                    }

                    Text {
                        font.family: Services.Fonts.family
                        width: 30
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.relTime(modelData.ts)
                        color: Services.Colors.textMuted
                        font.pixelSize: 10
                    }

                    Text {
                        font.family: Services.Fonts.family
                        width: 14
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: "×"
                        color: Services.Colors.textMuted
                        font.pixelSize: 13
                        opacity: hot.containsMouse || del.containsMouse ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Services.Motion.effectsFast }
                        }
                    }
                }

                // row click = copy + close (paste wherever you're headed)
                MouseArea {
                    id: hot
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.Clipboard.copy(index)
                }

                // declared after the row area so it takes the click in its
                // own footprint — dropping one entry, not copying it
                MouseArea {
                    id: del
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: parent.height
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.Clipboard.remove(index)
                }
            }
        }
    }
}
