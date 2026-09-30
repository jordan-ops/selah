import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Keybinding editor — the `keybinds` row type (a card): reads
// ~/.config/hypr/binds.lua, lists every top-level hl.bind statement
// (chord / action / trailing description), searches it, and writes
// changes back atomically with a `luac -p` guard:
//   · add     → appends hl.bind("chord", hl.dsp.exec_cmd("cmd"))  -- desc
//               (a chord that is already bound turns Add into Replace)
//   · remove  → deletes the statement's lines
//   · disable → comments every line of the statement (enable un-comments)
// Loops / conditionals are left alone: binds generated inside `for`
// blocks aren't listed (their chord only exists at runtime). Every save
// runs hyprctl reload through SettingsApp.reloadHypr(), which re-applies
// persisted + pending values so an un-Applied tweak survives.
Item {
    id: root

    // the renderer passes the catalog entry to every row component —
    // this row is fixed-config (no fields read), it just accepts it
    property var e: null

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    width: parent ? parent.width : 760
    height: col.implicitHeight

    property var lines: []          // raw file lines (write base)
    property var binds: []          // parsed: { start, end, chord, action, desc, disabled }
    property string filter: ""
    property string addChord: ""
    property string addCmd: ""
    property string addDesc: ""
    property string status: ""
    property string saveMsg: ""

    readonly property var shown: {
        const f = filter.trim().toLowerCase()
        if (f === "") return binds
        return binds.filter(b => b.chord.toLowerCase().indexOf(f) >= 0
            || b.action.toLowerCase().indexOf(f) >= 0
            || b.desc.toLowerCase().indexOf(f) >= 0)
    }
    readonly property string chordNorm: normalize(addChord)
    // enabled statements already using the typed chord → Add = Replace
    readonly property var clashList: {
        const n = root.chordNorm
        if (n === "") return []
        return root.binds.filter(b => !b.disabled && normalize(b.chord) === n)
    }
    readonly property bool clash: clashList.length > 0

    function normalize(s) {
        return String(s).toLowerCase()
            .replace(/\s*\+\s*/g, "+").replace(/\s+/g, " ").trim()
    }

    // ——————— lua helpers ———————
    // split on `..` concat operators, strings respected
    function splitConcat(s) {
        const out = []
        let cur = "", q = ""
        for (let i = 0; i < s.length; i++) {
            const c = s[i]
            if (q) {
                cur += c
                if (c === "\\" && i + 1 < s.length) { cur += s[++i]; continue }
                if (c === q) q = ""
                continue
            }
            if (c === '"' || c === "'") { q = c; cur += c; continue }
            if (c === "." && s[i + 1] === ".") { out.push(cur); cur = ""; i++; continue }
            cur += c
        }
        out.push(cur)
        return out
    }

    // mainMod .. " + W"  →  "SUPER + W"; unknown expr → null (skip row)
    function evalChord(expr, mainMod) {
        const parts = splitConcat(expr)
        let out = ""
        for (let i = 0; i < parts.length; i++) {
            const t = parts[i].trim()
            if (t === "") continue
            if (t[0] === '"' || t[0] === "'") {
                const q = t[0]
                let s = t.slice(1)
                if (s.length > 0 && s[s.length - 1] === q) s = s.slice(0, -1)
                out += s.replace(/\\(.)/g, "$1")
            } else if (t === "mainMod") out += mainMod
            else if (/^\w+$/.test(t)) out += t
            else return null
        }
        const chord = out.trim()
        return chord === "" ? null : chord
    }

    // first `--` outside quotes (the trailing description)
    function findComment(s, from) {
        let q = ""
        for (let i = from; i < s.length; i++) {
            const c = s[i]
            if (q) { if (c === "\\") { i++; continue } if (c === q) q = ""; continue }
            if (c === '"' || c === "'") { q = c; continue }
            if (c === "-" && s[i + 1] === "-") return i
        }
        return -1
    }

    // one hl.bind statement spanning lines[start…]: balance parens across
    // lines (quotes + escapes respected, the `-- ` disable prefix of a
    // commented statement skipped) and unpack chord / action / desc
    function statementAt(lines, start, mainMod) {
        const isDisabled = /^\s*--\s*hl\.bind\(/.test(lines[start])
        let d = 0, q = "", started = false, end = -1
        for (let j = start; j < lines.length && end < 0; j++) {
            const ln = lines[j]
            const lead = (ln.match(/^\s*/) || [""])[0].length
            for (let k = 0; k < ln.length; k++) {
                const c = ln[k]
                if (q) {
                    if (c === "\\") { k++; continue }
                    if (c === q) q = ""
                    continue
                }
                if (c === '"' || c === "'") { q = c; continue }
                if (isDisabled && !started && k >= lead && k <= lead + 1
                        && c === "-" && ln[k + 1] === "-") { k++; continue }
                if (c === "(") { d++; started = true }
                else if (c === ")") {
                    d--
                    if (started && d === 0) { end = j; break }
                }
            }
            if (end < 0 && j > start && ln.trim() === "") return null
        }
        if (end < 0) return null

        const rawLines = lines.slice(start, end + 1)
        const codeLines = isDisabled
            ? rawLines.map(l => l.replace(/^(\s*)--\s?/, "$1"))
            : rawLines
        let raw = codeLines.join("\n")

        const bindIdx = raw.indexOf("hl.bind(")
        if (bindIdx < 0) return null
        let desc = "", code = raw
        const cmt = findComment(raw, bindIdx + 8)
        if (cmt >= 0) {
            desc = raw.slice(cmt).split("\n")[0].replace(/^--\s*/, "").trim()
            code = raw.slice(0, cmt)
        }
        code = code.replace(/\s+$/, "")
        if (code[code.length - 1] !== ")") return null
        code = code.slice(0, -1)          // drop hl.bind's closing paren

        const open = code.indexOf("hl.bind(") + 8
        let cd = 1, cq = "", comma = -1
        for (let k = open; k < code.length; k++) {
            const c = code[k]
            if (cq) { if (c === "\\") { k++; continue } if (c === cq) cq = ""; continue }
            if (c === '"' || c === "'") { cq = c; continue }
            if (c === "(") cd++
            else if (c === ")") cd--
            else if (c === "," && cd === 1) { comma = k; break }
        }
        if (comma < 0) return null

        const chord = evalChord(code.slice(open, comma).trim(), mainMod)
        if (chord === null) return null
        return { start: start, end: end, chord: chord,
                 action: code.slice(comma + 1).trim(),
                 desc: desc, disabled: isDisabled }
    }

    // top-level statements only; loop/branch bodies are depth-skipped
    function parse(code) {
        const lines = code.split("\n")
        let mainMod = "SUPER"
        const mm = code.match(/local\s+mainMod\s*=\s*"([^"]*)"/)
        if (mm) mainMod = mm[1]

        const out = []
        let depth = 0, i = 0
        while (i < lines.length) {
            const t = lines[i].trim()
            if (/^end\b/.test(t)) {
                if (depth > 0) depth--
                i++
                continue
            }
            if (depth === 0) {
                const opens = (/^(for|while)\b/.test(t) && /\bdo\s*$/.test(t))
                    || (/^if\b/.test(t) && /\bthen\s*$/.test(t))
                    || (/^(local\s+)?function\b/.test(t) && !/\bend\s*$/.test(t))
                if (opens) { depth++; i++; continue }
                if (/^(\s*)(--\s*)?(?:local\s+\w+\s*=\s*)?hl\.bind\(/.test(lines[i])) {
                    const st = statementAt(lines, i, mainMod)
                    if (st) { out.push(st); i = st.end + 1; continue }
                }
            }
            i++
        }
        return out
    }

    function luaStr(s) {
        return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    }

    // ——————— io ———————
    function stageSave(newLines, msg) {
        if (wr.running) return
        root.saveMsg = msg
        root.status = "saving…"
        const path = Quickshell.env("HOME") + "/.config/hypr/binds.lua"
        wr.command = ["bash", "-c",
            'printf %s "$1" > "$2.tmp" && '
            + '{ ! command -v luac >/dev/null 2>&1 || luac -p "$2.tmp"; } && '
            + 'mv "$2.tmp" "$2" && echo SAVE_OK',
            "qs", newLines.join("\n") + "\n", path]
        wr.running = true
    }

    function addBind() {
        const chord = root.addChord.trim()
        const cmd = root.addCmd.trim()
        if (chord === "" || cmd === "") {
            root.status = "chord and command are both needed"
            return
        }
        const desc = root.addDesc.trim()
        const lines = root.lines.slice()
        const replacing = root.clashList.length > 0
        if (replacing) {
            const targets = root.clashList.slice()
                .sort((a, b) => b.start - a.start)
            for (let t = 0; t < targets.length; t++)
                lines.splice(targets[t].start,
                             targets[t].end - targets[t].start + 1)
        }
        let stmt = 'hl.bind("' + luaStr(chord) + '", hl.dsp.exec_cmd("'
            + luaStr(cmd) + '"))'
        if (desc !== "") stmt += "  -- " + desc.replace(/[\r\n]+/g, " ")
        lines.push(stmt)
        stageSave(lines, replacing
            ? "replaced “" + root.clashList[0].chord + "”"
            : "added “" + chord + "”")
    }

    function removeBind(b) {
        const lines = root.lines.slice()
        lines.splice(b.start, b.end - b.start + 1)
        stageSave(lines, "removed “" + b.chord + "”")
    }

    function toggleBind(b) {
        const lines = root.lines.slice()
        for (let i = b.start; i <= b.end; i++) {
            lines[i] = b.disabled
                ? lines[i].replace(/^(\s*)--\s?/, "$1")
                : lines[i].replace(/^(\s*)/, "$1-- ")
        }
        stageSave(lines, (b.disabled ? "enabled “" : "disabled “")
            + b.chord + "”")
    }

    Component.onCompleted: rd.running = true

    Process {
        id: rd
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/binds.lua"]
        stdout: StdioCollector {
            onStreamFinished: {
                const src = String(text)
                root.lines = src.trim() === "" ? []
                    : src.replace(/\n$/, "").split("\n")
                root.binds = root.parse(src)
            }
        }
    }

    Process {
        id: wr
        stdout: StdioCollector {
            onStreamFinished: {
                if (String(text).indexOf("SAVE_OK") >= 0) {
                    root.status = root.saveMsg
                    root.addChord = ""
                    root.addCmd = ""
                    root.addDesc = ""
                    rd.running = true
                    Services.SettingsApp.reloadHypr()
                } else {
                    root.status = "lua check failed — file not saved"
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

                // — search + "N of M" —
                Row {
                    width: inner.width
                    height: 26
                    spacing: 8

                    Rectangle {
                        width: inner.width - countTxt.width - 8
                        height: 26
                        radius: 8
                        color: Services.Colors.background
                        border.width: 1
                        border.color: searchInput.activeFocus
                            ? Services.Colors.accent : Services.Colors.low

                        TextInput {
                            font.family: Services.Fonts.family
                            id: searchInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            onTextChanged: if (text !== root.filter) root.filter = text

                            Text {
                                font.family: Services.Fonts.family
                                visible: searchInput.text === ""
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search chords or commands…"
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        id: countTxt
                        width: 76
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.shown.length + " of " + root.binds.length
                        color: Services.Colors.textMuted
                        font.pixelSize: 11
                    }
                }

                // — add / replace form —
                Row {
                    width: inner.width
                    height: 26
                    spacing: 8

                    Rectangle {
                        width: 168
                        height: 26
                        radius: 8
                        color: Services.Colors.background
                        border.width: 1
                        border.color: chordIn.activeFocus
                            ? Services.Colors.accent : Services.Colors.low

                        TextInput {
                            font.family: Services.Fonts.family
                            id: chordIn
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            text: root.addChord
                            onTextChanged: if (text !== root.addChord) root.addChord = text

                            Text {
                                font.family: Services.Fonts.family
                                visible: chordIn.text === "" && !chordIn.activeFocus
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "SUPER + SHIFT + X"
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        width: inner.width - 168 - descIn.width - addBtn.width - 24
                        height: 26
                        radius: 8
                        color: Services.Colors.background
                        border.width: 1
                        border.color: cmdIn.activeFocus
                            ? Services.Colors.accent : Services.Colors.low

                        TextInput {
                            font.family: Services.Fonts.family
                            id: cmdIn
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            text: root.addCmd
                            onTextChanged: if (text !== root.addCmd) root.addCmd = text

                            Text {
                                font.family: Services.Fonts.family
                                visible: cmdIn.text === "" && !cmdIn.activeFocus
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "command to run"
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        id: descIn
                        width: 132
                        height: 26
                        radius: 8
                        color: Services.Colors.background
                        border.width: 1
                        border.color: descF.activeFocus
                            ? Services.Colors.accent : Services.Colors.low

                        TextInput {
                            font.family: Services.Fonts.family
                            id: descF
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            text: root.addDesc
                            onTextChanged: if (text !== root.addDesc) root.addDesc = text

                            Text {
                                font.family: Services.Fonts.family
                                visible: descF.text === "" && !descF.activeFocus
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "description"
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
                        opacity: root.chordNorm === "" || root.addCmd.trim() === ""
                            ? 0.45 : 1

                        Text {
                            font.family: Services.Fonts.family
                            anchors.centerIn: parent
                            text: root.clash ? "Replace" : "Add"
                            color: Services.Colors.text
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: addBtnMa
                            anchors.fill: parent
                            enabled: root.chordNorm !== "" && root.addCmd.trim() !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addBind()
                        }
                    }
                }

                // — clash / status line —
                Text {
                    font.family: Services.Fonts.family
                    width: inner.width
                    height: 15
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    text: root.clash
                        ? "“" + root.clashList[0].chord + "” is already bound — “"
                            + root.clashList[0].action + "” · Add becomes Replace"
                        : root.status
                    color: root.clash ? Services.Colors.accent : Services.Colors.textMuted
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
                            height: 40
                            verticalAlignment: Text.AlignVCenter
                            visible: root.binds.length === 0
                            text: "couldn't read ~/.config/hypr/binds.lua"
                            color: Services.Colors.textMuted
                            font.pixelSize: 11
                        }
                        Text {
                            font.family: Services.Fonts.family
                            width: listCol.width
                            height: 40
                            verticalAlignment: Text.AlignVCenter
                            visible: root.binds.length > 0 && root.shown.length === 0
                            text: "no bindings match “" + root.filter + "”"
                            color: Services.Colors.textMuted
                            font.pixelSize: 11
                        }

                        Repeater {
                            model: root.shown

                            delegate: Item {
                                required property var modelData
                                required property int index
                                property var b: modelData
                                width: listCol.width
                                height: 36

                                Row {
                                    anchors.fill: parent
                                    spacing: 8

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: 190
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        text: b.chord
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: b.disabled
                                            ? Services.Colors.textMuted
                                            : Services.Colors.accent
                                    }

                                    Column {
                                        width: parent.width - 190 - 52 - 18 - parent.spacing * 3
                                        height: parent.height

                                        Text {
                                            font.family: Services.Fonts.family
                                            width: parent.width
                                            height: b.desc === "" ? parent.height : 18
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            // binds.lua carries some multi-line
                                            // commands — a literal \n breaks out
                                            // of the single-line elide and spills
                                            // over the desc row; flatten for display
                                            text: b.action.replace(/\s*\n\s*/g, " ")
                                            font.pixelSize: 11
                                            color: Services.Colors.textMuted
                                            opacity: b.disabled ? 0.5 : 1
                                        }
                                        Text {
                                            font.family: Services.Fonts.family
                                            visible: b.desc !== ""
                                            width: parent.width
                                            height: 16
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            text: b.desc
                                            font.pixelSize: 10
                                            color: Services.Colors.textMuted
                                            opacity: 0.65
                                        }
                                    }

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: 52
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: b.disabled ? "enable" : "disable"
                                        font.pixelSize: 10
                                        color: togMa.containsMouse
                                            ? Services.Colors.accent : Services.Colors.textMuted

                                        MouseArea {
                                            id: togMa
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleBind(b)
                                        }
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
                                            onClicked: root.removeBind(b)
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: Services.Colors.low
                                    opacity: index === root.shown.length - 1 ? 0 : 0.4
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
