pragma Singleton
import Quickshell
import QtQuick

// Toast queue for the settings window — the singleton holds the queue
// only; the snackbar itself draws inside the window (SettingsWindow's
// toastStack binds this model), so toasts sit above the footer, inside
// the card, never as their own layer surface.
//
// Root-level singletons resolve unprefixed from sibling files the same
// way widgets/GlobalStates.qml does for widgets/* — SettingsCmdSwitchRow
// and (later) the card files call SettingsToast.push(...) with no
// import. Push keeps the newest 3; the visual drops a toast after its
// 2.5s timer or on click, via drop(id).
Singleton {
    id: root

    property var queue: []   // [{ id, text, error }] — oldest first
    property int nextId: 1

    function push(text, error) {
        const q = root.queue.slice()
        q.push({ id: root.nextId, text: String(text), error: !!error })
        while (q.length > 3) q.shift()
        root.nextId += 1
        root.queue = q
    }

    function drop(id) {
        const q = []
        for (let i = 0; i < root.queue.length; i++)
            if (root.queue[i].id !== id) q.push(root.queue[i])
        root.queue = q
    }

    function clear() { root.queue = [] }
}
