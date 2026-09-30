pragma Singleton
import Quickshell

// This one's simple on purpose: no process, no polling — just a shared
// boolean, like a Waybar module toggling a CSS class. The actual "silencing"
// has to happen wherever you currently pop up a notification.
Singleton {
    id: root
    property bool enabled: false
    function toggle() { root.enabled = !root.enabled }
}

// --- Integration note for services/Notifications.qml ---
// Wherever you currently do something like:
//     onNotification: (n) => { pill.showNotification(n) }
// wrap it:
//     onNotification: (n) => {
//         if (!Services.DoNotDisturb.enabled) pill.showNotification(n)
//         history.push(n)   // still record it for the history panel below
//     }
// DND should stop the pill popup, not stop notifications from being
// received/logged — same as Waybar hiding a module without stopping
// the underlying data source.
