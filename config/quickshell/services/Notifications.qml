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

    // fired when quickshell is about to destroy a notification object (its
    // `closed` signal — expiry, action invoke, dismiss, remote close all
    // funnel through it). The object is deleted the moment these handlers
    // return, so every surface still holding it has to let go in the same
    // tick: history is plain JS, so nothing else would ever prune the
    // pointer — and clicking a row/chip that still pointed at the freed
    // object is what segfaulted the shell.
    signal notificationClosed(var notification)

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

    // actions worth a chip under a message row: blank text = the implicit
    // "default" marker (clicking the row already runs it) — everything
    // with a real label gets a button
    function chipsFor(notification) {
        if (!notification || !notification.actions) return []
        const acts = notification.actions, out = []
        for (let i = 0; i < acts.length; i++)
            if (acts[i].text) out.push(acts[i])
        return out
    }

    // ---- group + dismiss helpers (notification center + right-click) ----

    // group key for one notification: the app name, with a fallback so a
    // sloppy sender can't scatter its messages across "Unknown"/""/null
    function appName(n) { return (n && n.appName) ? n.appName : "Unknown" }

    // one app's history entries, newest-first — the center's group rows
    // read this in a binding, so any history change (arrival, dismiss,
    // clear) refreshes their contents without a model update
    function notifsFor(app) {
        const h = root.history, out = []
        for (let i = 0; i < h.length; i++)
            if (appName(h[i]) === app) out.push(h[i])
        return out
    }

    // unique app names, ordered by their newest member — a fresh message
    // bumps its group to the top of the center
    function groupNames() {
        const h = root.history, seen = {}, keys = []
        for (let i = 0; i < h.length; i++) {
            const k = appName(h[i])
            if (!seen[k]) { seen[k] = true; keys.push(k) }
        }
        return keys
    }

    // take a notification out of the center's log. Runs BEFORE dismiss()
    // so no delegate is left mid-read of an object we just closed.
    function removeHistory(n) {
        const idx = root.history.indexOf(n)
        if (idx === -1) return
        const h = root.history.slice()
        h.splice(idx, 1)
        root.history = h
    }

    // right-click dismiss: close the live notification AND drop it from
    // the center — dismissing from either surface means gone from both
    function dismissNotification(n) {
        if (!n) return
        root.removeHistory(n)
        n.dismiss()
    }

    // right-click a group header: dismiss every notification from that app
    function dismissApp(app) {
        const keep = [], h = root.history
        for (let i = 0; i < h.length; i++) {
            if (appName(h[i]) === app) h[i].dismiss()
            else keep.push(h[i])
        }
        root.history = keep
    }

    NotificationServer {
        id: server
        bodySupported: true
        imageSupported: true
        actionsSupported: true
        keepOnReload: false   // don't resurrect old notifications every time we reload quickshell during dev

        onNotification: function(notification) {
            notification.tracked = true   // must set this, or it's discarded immediately
            // drop it from the center (and let the pill know) the instant
            // quickshell closes it — runs BEFORE the delete, so the rows'
            // bindings re-evaluate while the object is still alive and no
            // delegate is left holding a dead reference
            notification.closed.connect(function() {
                root.removeHistory(notification)
                root.notificationClosed(notification)
            })
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

        // same code path as a right-click dismiss — clear the center
        // without a mouse (test passes, scripts)
        function dismissLatest(): void {
            if (root.history.length > 0)
                root.dismissNotification(root.history[0])
        }

        // same code path as clicking an action chip in the center
        function invokeChip(): void {
            if (root.history.length === 0) return
            const chips = root.chipsFor(root.history[0])
            if (chips.length > 0) chips[0].invoke()
        }

        // same code path as the center's "Clear all" pill
        function clear(): void {
            root.history = []
        }

        function count(): int {
            return root.history.length
        }
    }
}
