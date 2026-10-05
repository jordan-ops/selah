// Ported from Nebula's Widgets/CalendarOptionList.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var model: []
    spacing: 3

    Repeater {
        model: root.model

        delegate: CustomCard {
            id: optRow
            required property var modelData
            required property int index

            autoRadius: false
            topRadius: optRow.index === 0 ? 18 : 5
            bottomRadius: optRow.index === root.model.length - 1 ? 18 : 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    CustomText { content: optRow.modelData.label; size: 13 }
                    CustomText {
                        Layout.fillWidth: true
                        content: optRow.modelData.sub
                        size: 11
                        customColor: Colors.outline
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                }

                CustomToogle {
                    isToggleOn: SettingsConfig.widgets[optRow.modelData.key] ?? optRow.modelData.def
                    onToggled: state => {
                        const o = {}
                        o[optRow.modelData.key] = state
                        SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, o)
                    }
                }
            }
        }
    }
}
