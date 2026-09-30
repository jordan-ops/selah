import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Compose sequences — the `xcompose` row type (a card): reads
// ~/.XCompose (creating it with the standard `include "%L"` fallback on
// the first add), lists one row per `<seq> : "text"` entry, and writes
// additions/removals back atomically. Sequences typed without `<…>`
// wrappers get them (`o /` → `<Multi_key> <o> <slash>`; a leading
// <Multi_key> is implied unless the sequence already starts with
// Multi_key or a dead key) — the line under the form previews exactly
// what will be written. No reload: XCompose is read per-app, so new
// sequences apply to newly started programs.
Item {
    id: root

    // the renderer passes the catalog entry to every row component —
    // this row is fixed-config (no fields read), it just accepts it
    property var e: null

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    width: parent ? parent.width : 760
    height: col.implicitHeight

    property var lines: []        // raw file lines (write base)
    property var entries: []      // parsed: { idx, seq, value }
    property string addKeys: ""
    property string addVal: ""
    property string status: ""
    property string saveMsg: ""

    // single-char tokens → keysym names (</> would not resolve)
    readonly property var keysym: ({
        "/": "slash", "-": "minus", ".": "period", ",": "comma",
        "'": "apostrophe", '"': "quotedbl", ";": "semicolon", "=": "equal",
        "`": "grave", "[": "bracketleft", "]": "bracketright",
        "\\": "backslash", "*": "asterisk", "+": "plus", "#": "numbersign",
        "$": "dollar", "%": "percent", "&": "ampersand", "(": "parenleft",
        ")": "parenright", "!": "exclam", "?": "question", "@": "at",
        "^": "asciicircum", "~": "asciitilde", "<": "less", ">": "greater",
        "|": "bar", ":": "colon"
    })

    // "o /" → "<Multi_key> <o> <slash>"; "<a> <acute>" kept as typed
    function normSeq(s) {
        const toks = String(s).trim().split(/\s+/).filter(t => t !== "")
        const out = []
        for (let i = 0; i < toks.length; i++) {
            const t = toks[i]
            if (t.length >= 2 && t[0] === "<" && t[t.length - 1] === ">")
                out.push(t)
            else if (t.length === 1)
                out.push("<" + (root.keysym[t] || t) + ">")
            else
                out.push("<" + t + ">")
        }
        if (out.length === 0) return ""
        if (out[0] !== "<Multi_key>" && out[0].indexOf("<dead_") !== 0)
            out.unshift("<Multi_key>")
        return out.join(" ")
    }

    function normVal(s) {
        const t = String(s).trim()
        if (t === "") return ""
        if (t[0] === '"') return t
        return '"' + t.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
    }

    readonly property string seqNorm: normSeq(addKeys)
    readonly property var clashEntry: {
        const n = root.seqNorm
        if (n === "") return null
        return root.entries.find(en => en.seq.replace(/\s+/g, " ") === n)
    }
    readonly property bool clash: clashEntry !== null && clashEntry !== undefined
    readonly property bool canAdd: seqNorm !== "" && normVal(addVal) !== "" && !clash

    function parse(text) {
        const src = String(text)
        const lines = src.trim() === "" ? []
            : src.replace(/\n$/, "").split("\n")
        root.lines = lines
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim()
            if (t === "" || t[0] === "%" || t[0] === "#") continue
            const c = t.indexOf(":")
            if (c <= 0) continue
            out.push({ idx: i, seq: t.slice(0, c).trim(),
                       value: t.slice(c + 1).trim() })
        }
        return out
    }

    function stageSave(newLines, msg) {
        if (wr.running) return
        root.saveMsg = msg
        root.status = "saving…"
        const path = Quickshell.env("HOME") + "/.XCompose"
        wr.command = ["bash", "-c",
            'printf %s "$1" > "$2.tmp" && mv "$2.tmp" "$2" && echo SAVE_OK',
            "qs", newLines.join("\n") + "\n", path]
        wr.running = true
    }

    function addSeq() {
        const seq = root.seqNorm
        const val = normVal(root.addVal)
        if (seq === "" || val === "") {
            root.status = "sequence and text are both needed"
            return
        }
        if (root.clash) return
        const lines = root.lines.slice()
        if (lines.length === 0) lines = ['include "%L"']
        lines.push(seq + " : " + val)
        stageSave(lines, "added " + seq)
    }

    function removeSeq(en) {
        const lines = root.lines.slice()
        lines.splice(en.idx, 1)
        stageSave(lines, "removed " + en.seq)
    }

    Component.onCompleted: rd.running = true

    Process {
        id: rd
        command: ["cat", Quickshell.env("HOME") + "/.XCompose"]
        stdout: StdioCollector {
            onStreamFinished: root.entries = root.parse(text)
        }
    }

    Process {
        id: wr
        stdout: StdioCollector {
            onStreamFinished: {
                if (String(text).indexOf("SAVE_OK") >= 0) {
                    root.status = root.saveMsg
                    root.addKeys = ""
                    root.addVal = ""
                    rd.running = true
                } else {
                    root.status = "write failed — file not saved"
                }
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            // elevated card — SettingsPowerCard's visual language
            width: col.width
            height: inner.implicitHeight + 24
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Column {
                id: inner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                // — add form: keys + text + Add —
                Row {
                    width: inner.width
                    height: 26
                    spacing: 8

                    Rectangle {
                        width: 240
                        height: 26
                        radius: 8
                        color: Services.Colors.background
                        border.width: 1
                        border.color: seqIn.activeFocus
                            ? Services.Colors.accent : Services.Colors.low

                        TextInput {
                            font.family: Services.Fonts.family
                            id: seqIn
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            text: root.addKeys
                            onTextChanged: if (text !== root.addKeys) root.addKeys = text

                            Text {
                                font.family: Services.Fonts.family
                                visible: seqIn.text === "" && !seqIn.activeFocus
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "keys:  o /   or  <o> <slash>"
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        width: inner.width - 240 - addBtn.width - 16
                        height: 26
                        radius: 8
                        color: Services.Colors.background
                        border.width: 1
                        border.color: valIn.activeFocus
                            ? Services.Colors.accent : Services.Colors.low

                        TextInput {
                            font.family: Services.Fonts.family
                            id: valIn
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            text: root.addVal
                            onTextChanged: if (text !== root.addVal) root.addVal = text
                            onAccepted: if (root.canAdd) root.addSeq()

                            Text {
                                font.family: Services.Fonts.family
                                visible: valIn.text === "" && !valIn.activeFocus
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "replacement text"
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        id: addBtn
                        width: 62
                        height: 26
                        radius: 8
                        color: addBtnMa.containsMouse
                            ? Services.Colors.accent : Services.Colors.surfaceAlt
                        opacity: root.canAdd ? 1 : 0.45

                        Text {
                            font.family: Services.Fonts.family
                            anchors.centerIn: parent
                            text: "Add"
                            color: Services.Colors.text
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: addBtnMa
                            anchors.fill: parent
                            enabled: root.canAdd
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addSeq()
                        }
                    }
                }

                // — live preview of the line that will be written / clash —
                Text {
                    font.family: Services.Fonts.family
                    width: inner.width
                    height: 15
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    visible: text !== ""
                    text: root.clash
                        ? "“" + root.clashEntry.seq + "” is already defined — change the keys"
                        : root.seqNorm === "" ? ""
                        : root.seqNorm + " : " + normVal(root.addVal)
                    color: Services.Colors.accent
                    opacity: root.clash ? 1 : 0.85
                }

                // — status line —
                Text {
                    font.family: Services.Fonts.family
                    width: inner.width
                    height: 15
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    visible: text !== ""
                    text: root.status
                    color: Services.Colors.textMuted
                }

                // — header —
                Row {
                    width: inner.width
                    height: 16

                    Text {
                        font.family: Services.Fonts.family
                        width: parent.width - 90
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: "Your sequences — apply to newly opened apps"
                        color: Services.Colors.textMuted
                        font.pixelSize: 11
                    }
                    Text {
                        font.family: Services.Fonts.family
                        width: 90
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.entries.length + " entries"
                        color: Services.Colors.textMuted
                        font.pixelSize: 11
                    }
                }

                // — the list —
                Flickable {
                    id: flick
                    width: inner.width
                    height: 190
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentHeight: listCol.implicitHeight

                    Column {
                        id: listCol
                        width: flick.width

                        Text {
                            font.family: Services.Fonts.family
                            width: listCol.width
                            height: 44
                            verticalAlignment: Text.AlignVCenter
                            visible: root.entries.length === 0
                            text: "no sequences yet — the first Add creates\n"
                                + "~/.XCompose with the standard include \"%L\" fallback"
                            color: Services.Colors.textMuted
                            font.pixelSize: 11
                        }

                        Repeater {
                            model: root.entries

                            delegate: Item {
                                required property var modelData
                                required property int index
                                property var en: modelData
                                width: listCol.width
                                height: 32

                                Row {
                                    anchors.fill: parent
                                    spacing: 8

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: 300
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        text: en.seq
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Services.Colors.accent
                                    }

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: parent.width - 300 - 18 - parent.spacing * 2
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        text: en.value
                                        font.pixelSize: 11
                                        color: Services.Colors.textMuted
                                    }

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: 18
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: "✕"
                                        font.pixelSize: 12
                                        color: delMa.containsMouse
                                            ? Services.Colors.accent : Services.Colors.textMuted

                                        MouseArea {
                                            id: delMa
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeSeq(en)
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: Services.Colors.low
                                    opacity: index === root.entries.length - 1 ? 0 : 0.4
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
