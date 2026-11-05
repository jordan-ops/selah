pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// mango compositor state, bridged from the `mmsg` IPC.
//
// Four persistent `mmsg watch` streams keep the properties live; a
// one-shot `get` round seeds them at startup so the shell never has to
// wait for the first change event (and so it works even if a stream
// doesn't emit its initial state on connect). Every process is gated on
// MANGO_INSTANCE_SIGNATURE — under Hyprland this singleton is inert and
// spawns nothing.
//
// Data shapes (mango 0.18, all JSON):
//   watch all-monitors   {"monitors":[{name,active,x,y,width,height,scale,
//                                      tags:[...],active_tags:[...],
//                                      active_client:{...},...}]}
//   watch all-tags       {"all_tags":[{monitor,tags:[{index,is_active,
//                                      is_urgent,layout,client_count}]}]}
//   watch focusing-client {id,pid,title,appid,monitor,tags:[...],
//                                      is_fullscreen,is_floating,...} | null
//   watch all-clients    {"clients":[...same client shape...]}
//
// dispatch(cmd) is the action path: `mmsg dispatch <func>[,args...]`,
// serialized through a queue so rapid calls (key repeat) never race the
// one Process slot.
Singleton {
    id: root

    // Quickshell.env() yields null for an unset variable, not "" — test truthiness
    readonly property bool available: !!Quickshell.env("MANGO_INSTANCE_SIGNATURE")

    // ---- live state -------------------------------------------------
    property var monitors: []
    property var allTags: []
    property var clients: []
    property var focusedClient: null

    // ---- derived ----------------------------------------------------
    // Focused monitor = where the focused client lives, else the first
    // active monitor. mango has no "focused monitor" event (focus follows
    // the pointer), and for shell geometry (popup centering) the client's
    // output is the right answer; single-monitor setups are identical.
    readonly property var focusedMonitor: {
        const ms = root.monitors
        if (ms.length === 0) return null
        const fc = root.focusedClient
        if (fc)
            for (const m of ms)
                if (m.name === fc.monitor) return m
        for (const m of ms)
            if (m.active) return m
        return ms[0]
    }

    function monitorByName(name) {
        return root.monitors.find(m => m.name === name) ?? root.focusedMonitor
    }

    // tags of one monitor: [{index,is_active,is_urgent,layout,client_count}]
    function tagsFor(monName) {
        const entry = root.allTags.find(t => t.monitor === monName)
        if (entry) return entry.tags
        return root.monitorByName(monName)?.tags ?? []
    }

    // tags the monitor is currently viewing: [1] normally, [1,3] combo
    function activeTagsFor(monName) {
        return root.monitorByName(monName)?.active_tags ?? []
    }

    // ---- actions ----------------------------------------------------
    property var _queue: []

    function dispatch(cmd) {
        if (!root.available || !cmd) return
        root._queue.push(String(cmd))
        root._pump()
    }

    function _pump() {
        if (dispatchProc.running || root._queue.length === 0) return
        dispatchProc.command = ["mmsg", "dispatch", root._queue.shift()]
        dispatchProc.running = true
    }

    // ---- parsing ----------------------------------------------------
    // One line = one JSON doc. A parse failure is noise (a warning line
    // from mmsg) and gets dropped; a literal `null` is the focusing-client
    // stream saying "nothing focused" and must clear the state.
    function _ingest(line) {
        if (!line) return
        let o
        try { o = JSON.parse(line) } catch (e) { return }
        if (o === null) { root.focusedClient = null; return }
        if (o.monitors !== undefined) root.monitors = o.monitors
        else if (o.all_tags !== undefined) root.allTags = o.all_tags
        else if (o.clients !== undefined) root.clients = o.clients
        else if (o.id !== undefined) root.focusedClient = o      // focusing-client
    }

    // ---- processes --------------------------------------------------
    // Watch streams. A dead stream (compositor restart, mmsg upgrade)
    // schedules one shared reconnect timer that revives everything and
    // re-seeds — debounced so a teardown of all four doesn't restart
    // them four times over.
    Process {
        id: monWatch
        running: root.available
        command: ["mmsg", "watch", "all-monitors"]
        stdout: SplitParser { onRead: line => root._ingest(line) }
        onExited: reconnect.restart()
    }
    Process {
        id: tagWatch
        running: root.available
        command: ["mmsg", "watch", "all-tags"]
        stdout: SplitParser { onRead: line => root._ingest(line) }
        onExited: reconnect.restart()
    }
    Process {
        id: clientWatch
        running: root.available
        command: ["mmsg", "watch", "all-clients"]
        stdout: SplitParser { onRead: line => root._ingest(line) }
        onExited: reconnect.restart()
    }
    Process {
        id: focusWatch
        running: root.available
        command: ["mmsg", "watch", "focusing-client"]
        stdout: SplitParser { onRead: line => root._ingest(line) }
        onExited: reconnect.restart()
    }

    // One-shot seed: state within ~100ms of shell start, and again on
    // every reconnect (the gets are idempotent — the watches overwrite).
    Process {
        id: seedProc
        property int step: 0
        running: false
        command: ["mmsg", "get", "all-monitors"]
        stdout: SplitParser { onRead: line => root._ingest(line) }
        onExited: {
            if (!root.available) return
            step++
            if (step === 1) { command = ["mmsg", "get", "all-tags"]; running = true }
            else if (step === 2) { command = ["mmsg", "get", "all-clients"]; running = true }
            else if (step === 3) { command = ["mmsg", "get", "focusing-client"]; running = true }
            else step = 0
        }
    }

    Timer {
        id: reconnect
        interval: 1500
        onTriggered: {
            if (!root.available) return
            if (!monWatch.running) monWatch.running = true
            if (!tagWatch.running) tagWatch.running = true
            if (!clientWatch.running) clientWatch.running = true
            if (!focusWatch.running) focusWatch.running = true
            seedProc.step = 0
            seedProc.command = ["mmsg", "get", "all-monitors"]
            seedProc.running = true
        }
    }

    // Dispatch slot: one Process, fed from the queue. onExited pumps the
    // next command, so a burst of dispatches runs strictly in order.
    Process {
        id: dispatchProc
        running: false
        command: ["mmsg", "get", "version"]   // placeholder until first dispatch
        onExited: root._pump()
    }

    Component.onCompleted: {
        if (root.available) {
            seedProc.command = ["mmsg", "get", "all-monitors"]
            seedProc.running = true
        }
    }
}
