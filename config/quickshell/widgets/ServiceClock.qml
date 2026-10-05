// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's own
// clock service — no Nebula backend travels with us.
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    property var time: Qt.formatDateTime(clock.date, "h:mm a")
    property string hour: Qt.formatDateTime(clock.date, "hh")
    property string minute: Qt.formatDateTime(clock.date, "mm")
    property var seconds: Qt.formatDateTime(clock.date, "ss")
    property var day: Qt.formatDateTime(clock.date, "dddd")
    property var month: Qt.formatDateTime(clock.date, "MMMM")
    property var year: Qt.formatDateTime(clock.date, "yyyy")
    property var date: Qt.formatDateTime(clock.date, "dd")

    // Holidays — Nebula shelled out to its `nebula holidays` Python CLI
    // (Process + FileView cache + network fetch); that backend stays
    // behind, so the API shape survives with an always-empty answer.
    // Loaded/Attempted read true so consumers' retry guards settle
    // immediately instead of looping on a fetch that never comes.
    property var holidayData: []
    property int currentHolidayYear: new Date().getFullYear()
    property bool holidaysLoaded: true
    property bool holidayLoadAttempted: true

    // Country detection lived in Nebula's settings — with no loader
    // there is nothing to detect one for
    readonly property string holidayCountry: ""

    function loadHolidays() {
        // no-op: nothing to fetch, holidayData stays empty
    }

    function resetHolidays() {
        // no-op: nothing cached to clear
    }

    function ensureHolidaysForYear(year) {
        // no-op: an always-empty list is year-agnostic
    }

    function getMonthName(month) {
        const months = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        return months[month]
    }

    function getDaysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    function getFirstDayOfMonth(year, month) {
        return new Date(year, month, 1).getDay()
    }

    function checkHoliday(day, year, month) {
        if (!holidaysLoaded || !holidayData) {
            return { isHoliday: false, info: [] }
        }

        // Format date as YYYY-MM-DD for comparison
        const dateStr = year + "-" +
                        String(month + 1).padStart(2, '0') + "-" +
                        String(day).padStart(2, '0')

        // Find all holidays for this date (always none — see above)
        const holidays = holidayData.filter(h => h.date === dateStr)

        if (holidays.length > 0) {
            return {
                isHoliday: true,
                info: holidays.map(h => ({
                    name: h.name,
                    date: h.date,
                    dayOfWeek: h.dayOfWeek,
                    dayOfWeekShort: h.dayOfWeekShort
                }))
            }
        }

        return { isHoliday: false, info: [] }
    }

    function generateCalendarGrid(year, month, startDay) {
        let grid = []
        let daysInMonth = getDaysInMonth(year, month)
        let start = startDay === undefined ? 0 : (startDay % 7 + 7) % 7
        let firstDay = (getFirstDayOfMonth(year, month) - start + 7) % 7
        let today = new Date()

        // Get previous month info
        let prevMonth = month - 1
        let prevYear = year
        if (prevMonth < 0) {
            prevMonth = 11
            prevYear--
        }
        let daysInPrevMonth = getDaysInMonth(prevYear, prevMonth)

        // Add days from previous month
        for (let i = firstDay - 1; i >= 0; i--) {
            let day = daysInPrevMonth - i
            let holidayInfo = checkHoliday(day, prevYear, prevMonth)
            grid.push({
                day: day,
                month: "prev",
                monthIndex: prevMonth,
                year: prevYear,
                isHoliday: holidayInfo.isHoliday,
                info: holidayInfo.info,
                isCurrentMonth: false,
                isToday: today.getFullYear() === prevYear &&
                today.getMonth() === prevMonth &&
                today.getDate() === day
            })
        }

        // Add days of current month
        for (let day = 1; day <= daysInMonth; day++) {
            let holidayInfo = checkHoliday(day, year, month)
            grid.push({
                day: day,
                month: "current",
                monthIndex: month,
                year: year,
                isCurrentMonth: true,
                isHoliday: holidayInfo.isHoliday,
                info: holidayInfo.info,
                isToday: today.getFullYear() === year &&
                today.getMonth() === month &&
                today.getDate() === day
            })
        }

        // Add days from next month to fill the grid (42 cells = 6 rows)
        let remainingCells = Math.max(35, Math.ceil(grid.length / 7) * 7) - grid.length
        let nextMonth = month + 1
        let nextYear = year
        if (nextMonth > 11) {
            nextMonth = 0
            nextYear++
        }

        for (let day = 1; day <= remainingCells; day++) {
            let holidayInfo = checkHoliday(day, nextYear, nextMonth)
            grid.push({
                day: day,
                month: "next",
                monthIndex: nextMonth,
                year: nextYear,
                isCurrentMonth: false,
                isHoliday: holidayInfo.isHoliday,
                info: holidayInfo.info,
                isToday: today.getFullYear() === nextYear &&
                today.getMonth() === nextMonth &&
                today.getDate() === day
            })
        }

        return grid
    }
}
