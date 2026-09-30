pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The shell's font family — live, not read-once-at-startup.
//
// set-font.sh writes ~/.local/state/quickshell/current-font (the family
// only; the size half belongs to set-text-size.sh) but nothing in the
// shell ever read that file. Qt resolves a Text's font.family when the
// binding is first evaluated while quickshell starts, so every label kept
// drawing the OLD family until the shell was restarted — exactly the
// "font changes only show up after restarting quickshell" symptom.
//
// This is the missing wire: an inotify watch on the state file publishing
// the family as `Services.Fonts.family`.
//
// WHERE IT IS BOUND — every Text / TextEdit / TextInput in the shell, and
// nowhere else. That is not a style choice: Qt Quick's Item, Rectangle,
// Row… have NO `font` property at all (binding one is a hard QML error),
// and `Qt.application.font` is read-only and constant. A family therefore
// cannot be set on a window root or a container and inherited — the only
// element that can carry it is the text renderer itself.
//
// Adding text later? Put `font.family: Services.Fonts.family` on the
// Text (an import of "./services" as Services is already the house
// style). Without it that one label falls back to the family quickshell
// happened to start with, so it would look wrong after the next font
// change until the shell restarts — SUPER+SHIFT+R papers over it.
Singleton {
    id: root

    // What everything resolves to before the state file exists (fresh
    // install) or if it comes back empty — fontconfig's own alias, so it
    // always lands on a real font rather than on a family nobody has.
    readonly property string fallbackFamily: "monospace"
    property string family: fallbackFamily

    readonly property string statePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/current-font"

    // `onTextChanged` is what actually delivers: it fires off the reload
    // triggered below, at the same millisecond set-font.sh writes. `loaded`
    // is kept as the belt-and-braces path (initial read, and any read that
    // lands without a text notification). Measured latency from the write
    // to a Text picking the family up: 6-45 ms.
    function sync() {
        const raw = String(fontFile.text()).trim()
        root.family = raw.length > 0 ? raw : root.fallbackFamily
    }

    FileView {
        id: fontFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: root.sync()
        onTextChanged: root.sync()
        // set-font.sh truncates and rewrites the file in place; one watch
        // event can arrive mid-write, so re-read until the content settles.
        onFileChanged: reload()
    }
}
