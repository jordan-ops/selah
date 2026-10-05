.pragma library

var SYNODIC = 29.530588853
var FULL_AGE = SYNODIC / 2
var NEW_REF = Date.UTC(2000, 0, 6, 18, 14)

function moonAge(date) {
    var days = (date.getTime() - NEW_REF) / 86400000
    return ((days % SYNODIC) + SYNODIC) % SYNODIC
}

function moonIllum(age) {
    return (1 - Math.cos(2 * Math.PI * age / SYNODIC)) / 2
}

function moonPhaseName(age) {
    var names = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
                 "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
    var i = Math.floor((age / SYNODIC) * 8 + 0.5) % 8
    return names[i]
}

function daysUntilAge(age, target) {
    return ((target - age) % SYNODIC + SYNODIC) % SYNODIC
}

function moonDaysInMonth(year, month) {
    var n = new Date(year, month + 1, 0).getDate()
    var full = [], fresh = []
    for (var d = 1; d <= n; d++) {
        var a = moonAge(new Date(year, month, d, 12))
        if (Math.abs(a - FULL_AGE) < 0.51) full.push(d)
        if (a < 0.51 || a > SYNODIC - 0.51) fresh.push(d)
    }
    return { full: full, fresh: fresh }
}

function moonPath(cx, cy, r, age) {
    var k = moonIllum(age)
    var waxing = age < FULL_AGE
    var gibbous = k > 0.5
    var rx = r * Math.abs(2 * k - 1)
    var limb = waxing ? 1 : 0
    var term = waxing ? (gibbous ? 1 : 0) : (gibbous ? 0 : 1)
    return "M " + cx + " " + (cy - r)
        + " A " + r + " " + r + " 0 0 " + limb + " " + cx + " " + (cy + r)
        + " A " + rx.toFixed(2) + " " + r + " 0 0 " + term + " " + cx + " " + (cy - r) + " Z"
}

function dayOfYear(date) {
    var start = new Date(date.getFullYear(), 0, 1)
    return Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - start) / 86400000) + 1
}

function daysInYear(year) {
    return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0 ? 366 : 365
}

function isoWeek(date) {
    var d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    var day = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - day)
    var yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
}

function parseClock(str) {
    var m = String(str || "").match(/(\d{1,2}):(\d{2})\s*(AM|PM)?/i)
    if (!m) return -1
    var h = parseInt(m[1]), min = parseInt(m[2])
    var ap = m[3] ? m[3].toUpperCase() : ""
    if (ap === "PM" && h !== 12) h += 12
    if (ap === "AM" && h === 12) h = 0
    return h * 60 + min
}

function fmtClock(mins) {
    var h = Math.floor(mins / 60), m = mins % 60
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

function fmtDuration(mins) {
    mins = Math.max(0, Math.round(mins))
    var h = Math.floor(mins / 60), m = mins % 60
    if (h === 0) return m + " m"
    return h + " h " + (m < 10 ? "0" : "") + m + " m"
}

function upcomingHolidays(list, today, limit) {
    var out = []
    var seen = {}
    var base = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    var sorted = (list || []).slice().sort(function (a, b) { return a.date < b.date ? -1 : a.date > b.date ? 1 : 0 })
    for (var i = 0; i < sorted.length && out.length < limit; i++) {
        var h = sorted[i]
        var p = String(h.date).split("-")
        var d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]))
        if (d <= base || seen[h.date]) continue
        seen[h.date] = true
        out.push({ name: h.name, date: d, days: Math.round((d - base) / 86400000) })
    }
    return out
}
