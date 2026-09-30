pragma Singleton
import Quickshell
import QtQuick

Singleton{
    id:root
    readonly property string time:{
        return Qt.formatDateTime(clock.date,"hh:mm")
    }
    // bar's expanded row shows a date now (settings-app era: one source)
    readonly property string date:{
        return Qt.formatDateTime(clock.date, "ddd d MMM")
    }

    SystemClock{
        id:clock
        precision: SystemClock.Minutes
    }
}