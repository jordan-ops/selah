// Ported from Nebula's Widgets/ClockOptions.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property var rows: []

    spacing: 3

    Repeater {
        model: [{ key: "clockUse24", label: "24-hour time", def: false },
                { key: "clockShowDate", label: "Show date", def: true }].concat(root.rows)

        delegate: CustomCard {
            id: row
            required property var modelData
            required property int index
            readonly property int count: 2 + root.rows.length

            autoRadius: false
            topRadius: row.index === 0 ? 18 : 5
            bottomRadius: row.index === row.count - 1 ? 18 : 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    CustomText { content: row.modelData.label; size: 13 }
                    CustomText {
                        visible: (row.modelData.sub ?? "") !== ""
                        Layout.fillWidth: true
                        content: row.modelData.sub ?? ""
                        size: 11
                        customColor: Colors.outline
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                }

                CustomToogle {
                    isToggleOn: SettingsConfig.widgets[row.modelData.key] ?? row.modelData.def
                    onToggled: state => {
                        const o = {}
                        o[row.modelData.key] = state
                        SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, o)
                    }
                }
            }
        }
    }
}
