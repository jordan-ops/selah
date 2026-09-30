pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Io

// Task list for the clock card. Persisted to
// ~/.local/state/quickshell/tasks.json (same FileView + argv-form printf
// pattern as battery-history/weather), so reloads, theme switches and
// reboots don't eat the list.
Singleton {
    id: root

    readonly property string tasksPath:
        Quickshell.env("HOME") + "/.local/state/quickshell/tasks.json"

    property var items: []   // [{ id, text, done }]

    FileView {
        path: root.tasksPath
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (Array.isArray(d.items)) root.items = d.items
            } catch (e) {
                console.log("Tasks: parse —", e)
            }
        }
    }

    Process { id: tw }   // cache writer

    function persist() {
        tw.command = ["sh", "-c", "printf %s \"$1\" > \"$2\"", "taskwrite",
                      JSON.stringify({ items: root.items }), root.tasksPath]
        tw.running = false
        tw.running = true
    }

    function addTask(text) {
        const trimmed = text.trim()
        if (trimmed === "") return
        root.items = root.items.concat([{ id: Date.now(), text: trimmed, done: false }])
        persist()
    }

    function toggleTask(id) {
        root.items = root.items.map(t =>
            t.id === id ? Object.assign({}, t, { done: !t.done }) : t)
        persist()
    }

    function removeTask(id) {
        root.items = root.items.filter(t => t.id !== id)
        persist()
    }
}
