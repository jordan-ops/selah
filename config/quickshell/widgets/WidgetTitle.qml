// Ported from Nebula's Widgets/WidgetTitle.qml (GPL-3.0) — qs.modules
// imports dropped: WidgetSizes, Colors and the kit are siblings.
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property string icon: ""
    property string title: ""
    property string detail: ""

    spacing: 6

    MaterialIconSymbol {
        content: root.icon
        iconSize: 17
        customColor: Colors.primary
    }
    CustomText {
        content: root.title
        size: 13
        weight: 600
        customColor: Colors.primary
    }
    Item { Layout.fillWidth: true }
    CustomText {
        visible: root.detail !== ""
        content: root.detail
        size: 11
        weight: 500
        customColor: Colors.surfaceVariantText
    }
}
