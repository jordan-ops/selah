import Quickshell
import QtQuick

ShellRoot{
    Background{}
    Bar{}
    LockScreen{}
    AetherPicker{}   // aether wallpaper/palette overlay — qs ipc call aether toggle
    RepoUpdatePopup{}   // "a new deploy is ready" dialog — qs ipc call updates status
    // MediaBar{}
    // NotificationBar {}
    // Motion tokens (Material 3 Expressive durations/beziers/springs): services/Motion.qml
}
