// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's own
// tasks service — no Nebula backend travels with us.
pragma Singleton

import Quickshell
import QtQuick
import "../services" as Services

Singleton {
    id: root

    // Nebula's todo shape is richer than our {id, text, done} rows; the
    // fields we can't answer ship empty. items is reassigned (never
    // mutated) on every change, so the mapping binding re-fires then.
    readonly property var todos: Services.Tasks.items.map(t => ({
        id: String(t.id),
        title: t.text,
        description: "",
        completed: t.done,
        completedAt: "",
        priority: 0,
        tags: [],
        dueDate: "",
        createdAt: "",
        updatedAt: ""
    }))

    // Computed from the shape rather than hardcoded, so overdue/highPriority
    // light up the day our rows gain real dates — for now dueDate is always
    // "" and priority always 0, which is exactly why they read zero.
    readonly property var stats: {
        const done = root.todos.filter(t => t.completed).length
        return {
            total: root.todos.length,
            active: root.todos.length - done,
            completed: done,
            overdue: root.todos.filter(t => !t.completed && root.isOverdue(t)).length,
            dueToday: 0,
            highPriority: root.todos.filter(t => (t.priority ?? 0) >= 3).length
        }
    }

    // no due dates on our side — nothing can ever be overdue
    function isOverdue(todo) {
        return false
    }

    // The widget passes modelData.dueDate (a string), not the todo, and
    // only after gating the chip's visible on dueDate !== "" — our shape
    // always ships "", so this label never renders and no empty pill can
    // appear. Returning "" (not null) keeps it safe if that gate ever
    // changes.
    function dueDateLabel(dueDate) {
        return ""
    }

    // The widget hands us modelData.id (a string); accept a todo too
    function toggleComplete(t) {
        Services.Tasks.toggleTask(Number(typeof t === "object" ? t.id : t))
    }

    function removeTodo(t) {
        Services.Tasks.removeTask(Number(typeof t === "object" ? t.id : t))
    }

    // Quick-add calls addTodo(title, description, priority, tags, dueDate);
    // our store keeps the text alone, the rest is dropped
    function addTodo(title, description, priority, tags, dueDate) {
        Services.Tasks.addTask(title)
    }
}
