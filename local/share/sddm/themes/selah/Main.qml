// Selah greeter — the login screen, branded like everything else.
//
// Vanilla QtQuick only (no SddmComponents import): fewer moving parts on
// the one screen that must never fail to render. SDDM injects these as
// context properties: sddm (login/power), userModel, sessionModel.
//
// Wallpaper + palette are generated into assets/ by
// scripts/selah-sddm.sh sync (wallpaper copy + vars.js out of
// colors.json), so the greeter follows the shell theme; switch-theme.sh
// runs that sync on every switch, and the installed copy refreshes
// itself once the one-time sudo setup exists.
import QtQuick 2.15   // versioned: the greeter runs Qt5 (sddm-greeter → libQt5Quick), which rejects versionless imports
import "assets/vars.js" as V

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: V.background
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 400 } }

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // index handed to sddm.login — starts on SDDM's remembered default
    property int sessionIndex: sessionModel.lastIndex
    property string statusMsg: ""

    function tryLogin() {
        if (userField.text === "") {
            statusMsg = "Enter a username"
            userField.forceActiveFocus()
            return
        }
        statusMsg = ""
        sddm.login(userField.text, passField.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            passField.text = ""
            statusMsg = "Login failed — check the password"
            passField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            statusMsg = ""
        }
    }

    // — wallpaper + dim, so every theme's colors stay readable —
    Image {
        anchors.fill: parent
        source: "assets/background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: {
            if (status === Image.Error)
                source = ""
        }
    }
    Rectangle { anchors.fill: parent; color: "#73000000" }

    // — clock —
    Column {
        anchors.top: parent.top
        anchors.topMargin: Math.round(parent.height * 0.085)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            color: V.on_background
            font.pixelSize: 68
            font.bold: true
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            color: V.on_background
            opacity: 0.7
            font.pixelSize: 15
            text: Qt.formatDate(new Date(), "dddd, d MMMM yyyy")
        }
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: {
                timeText.text = Qt.formatTime(new Date(), "HH:mm")
                dateText.text = Qt.formatDate(new Date(), "dddd, d MMMM yyyy")
            }
        }
    }

    // — logo + login card —
    Column {
        anchors.centerIn: parent
        spacing: 30

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 210
            height: 210
            source: "assets/logo.png"
            fillMode: Image.PreserveAspectFit
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            width: 420
            height: cardCol.implicitHeight + 40
            radius: 16
            color: V.secondary_container
            border.color: V.outline
            border.width: 1

            Column {
                id: cardCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 20
                spacing: 10

                Rectangle {
                    id: userBox
                    width: parent.width
                    height: 46
                    radius: 10
                    color: V.background
                    border.color: userField.activeFocus ? V.primary : V.outline
                    border.width: userField.activeFocus ? 2 : 1

                    TextInput {
                        id: userField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: V.on_background
                        font.pixelSize: 14
                        // single-account box: preselect the user so the
                        // greeter opens straight on the password field.
                        // lastUser = SDDM's remembered user (root-readable
                        // state file — set at a real boot, empty in
                        // --test-mode), so fall back to the first entry of
                        // the local user model.
                        text: {
                            if (userModel.lastUser !== "")
                                return userModel.lastUser
                            if (userModel.count > 0)
                                // NameRole = Qt::UserRole + 1 (SDDM source);
                                // the Q_ENUM isn't reachable on a context
                                // property, so pass the role number directly
                                return userModel.data(userModel.index(0, 0), 257)
                            return ""
                        }
                        clip: true
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                passField.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                    }
                    Text {
                        visible: userField.text === ""
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: V.on_surface_variant
                        font.pixelSize: 14
                        text: "Username"
                    }
                }

                Rectangle {
                    id: passBox
                    width: parent.width
                    height: 46
                    radius: 10
                    color: V.background
                    border.color: passField.activeFocus ? V.primary : V.outline
                    border.width: passField.activeFocus ? 2 : 1

                    TextInput {
                        id: passField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: V.on_background
                        font.pixelSize: 14
                        echoMode: TextInput.Password
                        clip: true
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.tryLogin()
                                event.accepted = true
                            }
                        }
                    }
                    Text {
                        visible: passField.text === ""
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: V.on_surface_variant
                        font.pixelSize: 14
                        text: "Password"
                    }
                }

                Text {
                    id: statusText
                    width: parent.width
                    height: 16
                    color: V.error
                    font.pixelSize: 12
                    text: root.statusMsg
                }

                Rectangle {
                    id: loginBtn
                    width: parent.width
                    height: 46
                    radius: 10
                    color: V.primary
                    opacity: loginArea.pressed ? 0.85 : 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        color: V.background
                        font.pixelSize: 14
                        font.bold: true
                        text: "Log in"
                    }
                    MouseArea {
                        id: loginArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tryLogin()
                    }
                }
            }
        }
    }

    // — footer: session chips (left), power (right) —
    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.bottomMargin: 24
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: V.on_background
            opacity: 0.6
            font.pixelSize: 12
            text: "Session:"
        }

        Repeater {
            model: sessionModel
            delegate: Rectangle {
                // once a delegate declares ANY required property, roles are
                // only injected as required properties (model.* goes away)
                required property int index
                required property string name
                width: sessLabel.implicitWidth + 26
                height: 30
                radius: 15
                color: index === root.sessionIndex ? V.primary : V.secondary_container
                opacity: index === root.sessionIndex ? 1 : 0.8

                Text {
                    id: sessLabel
                    anchors.centerIn: parent
                    color: index === root.sessionIndex ? V.background : V.on_background
                    font.pixelSize: 12
                    font.bold: index === root.sessionIndex
                    text: name
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sessionIndex = index
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        spacing: 8

        Rectangle {
            visible: sddm.canSuspend
            width: suspLabel.implicitWidth + 26
            height: 30
            radius: 15
            color: V.secondary_container
            opacity: suspArea.containsMouse ? 1 : 0.8
            Text {
                id: suspLabel
                anchors.centerIn: parent
                color: V.on_background
                font.pixelSize: 12
                text: "Suspend"
            }
            MouseArea {
                id: suspArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.suspend()
            }
        }
        Rectangle {
            width: rebootLabel.implicitWidth + 26
            height: 30
            radius: 15
            color: V.secondary_container
            opacity: rebootArea.containsMouse ? 1 : 0.8
            Text {
                id: rebootLabel
                anchors.centerIn: parent
                color: V.on_background
                font.pixelSize: 12
                text: "Reboot"
            }
            MouseArea {
                id: rebootArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.reboot()
            }
        }
        Rectangle {
            width: offLabel.implicitWidth + 26
            height: 30
            radius: 15
            color: V.secondary_container
            opacity: offArea.containsMouse ? 1 : 0.8
            Text {
                id: offLabel
                anchors.centerIn: parent
                color: V.on_background
                font.pixelSize: 12
                text: "Shut down"
            }
            MouseArea {
                id: offArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.powerOff()
            }
        }
    }

    Component.onCompleted: {
        root.opacity = 1
        if (userField.text === "")
            userField.forceActiveFocus()
        else
            passField.forceActiveFocus()
    }
}
