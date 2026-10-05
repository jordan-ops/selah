// Ported from Nebula's Widgets/WidgetCard.qml (GPL-3.0) — only the
// qs.modules.utils import dropped: WidgetSizes is a sibling.
import QtQuick

Rectangle {
    id: card

    readonly property real pad: WidgetSizes.padFor(card.width)

    radius: WidgetSizes.radius
    color: WidgetSizes.cardColor
}
