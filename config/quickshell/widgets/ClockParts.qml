// Ported from Nebula's Widgets/ClockParts.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick

QtObject {
    id: root

    readonly property bool use24: SettingsConfig.widgets.clockUse24 ?? false
    readonly property bool showDate: SettingsConfig.widgets.clockShowDate ?? true
    readonly property int hour24: parseInt(ServiceClock.hour)
    readonly property string hour: root.use24 ? ServiceClock.hour
        : String(root.hour24 % 12 === 0 ? 12 : root.hour24 % 12)
    readonly property string hourPad: root.hour.length < 2 ? "0" + root.hour : root.hour
    readonly property string minute: ServiceClock.minute
    readonly property int second: parseInt(ServiceClock.seconds)
    readonly property string ampm: root.use24 ? "" : (root.hour24 < 12 ? "AM" : "PM")
    readonly property string weekday: ServiceClock.day
    readonly property string month: ServiceClock.month
    readonly property int day: parseInt(ServiceClock.date)
    readonly property string time: root.hour + ":" + root.minute
}
