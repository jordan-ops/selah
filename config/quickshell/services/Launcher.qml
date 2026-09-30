pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool open: false

    // Multi-monitor: overlay state is shared, but every screen has its own
    // bar. The bar that opens this overlay records itself here and only it
    // reacts — without an owner, every bar showed the panel AND armed its
    // own HyprlandFocusGrab; the duplicate grabs fought over keyboard focus
    // and cleared each other the instant they activated, so no panel ever
    // appeared once a second display was connected.
    property string ownerScreen: ""
    onOpenChanged: {
        if (open) {
            const fm = Hyprland.focusedMonitor
            ownerScreen = fm ? fm.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        }
    }
    property string query: ""
    property int selectedIndex: 0

    // typing rebuilds `results` — snap the selection back to the top so the
    // pill always has a row to land on (a stale index past the new result
    // count would leave nothing selected at all)
    onQueryChanged: selectedIndex = 0

    // deletion (model churn) can shrink the list under the selection just
    // as easily — keep the index inside the model so the pill always has a
    // row to land on
    onResultsChanged: {
        if (selectedIndex >= results.length)
            selectedIndex = Math.max(0, results.length - 1)
    }

    // --- delete-from-launcher (Delete key → confirm dialog) ------------
    property bool confirmDelete: false
    property int confirmChoice: 1     // 0 = yes, 1 = no; opens ON no so a
                                      // stray Enter can never delete
    property var confirmEntry: null   // frozen at request time: the dialog
                                      // must act on the row that opened it

    function selectedEntry() {
        if (results.length === 0) return null
        return results[Math.min(selectedIndex, results.length - 1)]
    }

    // Settings rows are not installed software — only DesktopEntry rows
    // carry an id (quickshell's desktop-file identity).
    function removable(e) {
        return e != null && typeof e.id === "string" && e.id !== ""
    }

    // both installer generations count as a web app: webapp-launch.sh
    // URLs and the omarchy tool's chromium --app= launchers
    function isWebapp(e) {
        const x = (e != null && e.execString) || ""
        return x.includes("webapp-launch.sh") || x.includes("--app=")
    }

    function requestDelete() {
        const e = selectedEntry()
        if (!removable(e)) return
        confirmEntry = e
        confirmChoice = 1
        confirmDelete = true
    }

    function confirmCancel() {
        confirmDelete = false
        confirmEntry = null
    }

    function confirmAccept() {
        if (!confirmDelete) return
        const e = confirmEntry
        const go = confirmChoice === 0 && removable(e)
        confirmDelete = false
        confirmEntry = null
        if (!go) return
        closeLauncher()
        // detached: the webapp branch finishes silently; the system branch
        // reopens itself under a floating foot (remove-app.sh explains why)
        Quickshell.execDetached([Quickshell.shellPath("scripts/remove-app.sh"), e.id])
    }

    function pageMeta(id) {
        return SettingsCatalog.pages.find(p => p.id === id)
            || { name: "Setting", icon: "preferences-system" }
    }

    readonly property var results: {
    const q = query.trim().toLowerCase()

    // settings are first-class results: the catalog itself is the index
    // (omasettings' lesson — no second list to maintain), matches sit
    // above app hits and deep-link into the window on page + row.
    const settings = q === "" ? [] : SettingsCatalog.entries.filter(e => {
        const hay = [e.label, e.description, e.keywords, pageMeta(e.page).name]
            .filter(Boolean).join(" ").toLowerCase()
        return q.split(/\s+/).every(t => hay.includes(t))
    }).slice(0, 8).map(e => ({
        name: e.label,
        comment: pageMeta(e.page).name + " — " + (e.description || "Setting"),
        icon: pageMeta(e.page).icon,
        execute: () => SettingsApp.show(e.page, e.id)
    }))

    const apps = [...DesktopEntries.applications.values]
        .filter(d => d.name)
        .sort((a, b) => a.name.localeCompare(b.name))
        .filter(d => {
            if (q === "") return true
            const name = (d.name || "").toLowerCase()
            const comment = (d.comment || "").toLowerCase()
            return name.includes(q) || comment.includes(q)
        })
        .slice(0, q === "" ? 50 : 40)

    return [...settings, ...apps]
}

    function openLauncher() {
        query = ""
        selectedIndex = 0
        confirmDelete = false
        confirmEntry = null
        open = true
    }

    function closeLauncher() {
        open = false
        query = ""
        // a close must never leave a stale dialog armed for the next open
        confirmDelete = false
        confirmEntry = null
    }

    function moveSelection(delta) {
        if (results.length === 0) return
        selectedIndex = (selectedIndex + delta + results.length) % results.length
    }

    function launchSelected() {
        if (results.length === 0) return
        results[Math.min(selectedIndex, results.length - 1)].execute()
        closeLauncher()
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (root.open) root.closeLauncher()
            else root.openLauncher()
        }
        // same shape as tray count / clipboard count: how many apps the
        // launcher can actually see. Doubles as the check that a freshly
        // created .desktop has been picked up (it only changes on restart).
        function count(): string {
            return String(DesktopEntries.applications.values.length)
        }
    }
}