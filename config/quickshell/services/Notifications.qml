pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    readonly property alias list: server.trackedNotifications

    // newest-first history of live notification objects for the control
    // center (capped) — live objects so rows can still invoke actions
    // after the bar pill has faded back to its normal content.
    property var history: []

    // fired once per incoming notification — separate from `list` changing,
    // since `list` also changes on dismiss/expire and we only want to react to arrivals
    signal newNotification(var notification)

    // Click handler shared by the bar pill and the history rows: invokes
    // the notification's "default" action, or its first action — this is
    // what turns a click on "Screenshot taken" into tensaku opening.
    function invokeDefault(notification) {
        if (!notification) return
        const acts = notification.actions
        if (!acts || acts.length === 0) return
        let target = acts[0]
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].identifier === "default") {
                target = acts[i]
                break
            }
        }
        target.invoke()
    }

    NotificationServer {
        id: server
        bodySupported: true
        imageSupported: true
        actionsSupported: true
        keepOnReload: false   // don't resurrect old notifications every time we reload quickshell during dev

        onNotification: function(notification) {
            notification.tracked = true   // must set this, or it's discarded immediately
            root.history = [notification].concat(root.history).slice(0, 50)
            root.newNotification(notification)
        }
    }

    IpcHandler {
        target: "notifications"

        // same code path as a pill click — lets scripts test the
        // notification → action → exec chain without a real mouse
        function invokeLatest(): void {
            if (root.history.length > 0)
                root.invokeDefault(root.history[0])
        }
    }
}
