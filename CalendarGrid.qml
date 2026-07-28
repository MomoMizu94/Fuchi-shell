import QtQuick
import QtQuick.Layouts
import "config.js" as Config

// Shared month grid (8 columns: ISO week number + Mon…Sun), used full-size by
// Tabs/CalendarTab.qml and compact by Bar/CalendarMenu.qml. Defaults preserve
// the original Dashboard calendar look.
ColumnLayout {
    id: grid

    property int year: new Date().getFullYear()
    property int month: new Date().getMonth() + 1   // 1-12

    // Sizing knobs (defaults = the Dashboard tab's original literals)
    property int cellHeight: 56
    property int todaySize: 60
    property int cellSpacing: 25
    property int dowFontSize: Config.bar.fontSize + 10
    property int dayFontSize: Config.bar.fontSize + 10
    property int weekFontSize: Config.bar.fontSize + 4

    // Selection / events (used by the menu; inert by default)
    property bool showSelection: false
    property string selectedDate: ""       // ISO "YYYY-MM-DD"
    property var eventDates: ({})          // { "YYYY-MM-DD": true, ... }
    signal dayClicked(string isoDate)

    // Matches the original CalendarTab root-column spacing between the DOW
    // header and the day grid.
    spacing: 6

    function isoWeek(year, month, day) {
        const d = new Date(year, month - 1, day)
        const dow = d.getDay() || 7
        d.setDate(d.getDate() + 4 - dow)
        const yearStart = new Date(d.getFullYear(), 0, 1)
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7)
    }

    // Resolve a (possibly spill) day cell to its true year/month
    function cellDate(cell) {
        let y = grid.year, m = grid.month
        if (!cell.cur) {
            // Spill days in the first row belong to the previous month,
            // in the last row to the next month.
            if (cell.firstRow) { if (m === 1) { m = 12; y-- } else m-- }
            else               { if (m === 12) { m = 1; y++ } else m++ }
        }
        return y + "-" + String(m).padStart(2, "0") + "-" + String(cell.d).padStart(2, "0")
    }

    function calendarDays() {
        const fw      = (new Date(year, month - 1, 1).getDay() + 6) % 7
        const dim     = new Date(year, month, 0).getDate()
        const prevDim = new Date(year, month - 1, 0).getDate()
        const days = []
        for (let i = fw - 1; i >= 0; i--)
            days.push({ d: prevDim - i, cur: false })
        for (let i = 1; i <= dim; i++)
            days.push({ d: i, cur: true })
        const rem = (7 - days.length % 7) % 7
        for (let i = 1; i <= rem; i++)
            days.push({ d: i, cur: false })

        // Interleave a week-number sentinel at the start of each 7-day row,
        // and tag cells with their row position so spill days can be resolved
        // to the correct neighbouring month.
        const result = []
        const rows = days.length / 7
        for (let row = 0; row < rows; row++) {
            const slice = days.slice(row * 7, row * 7 + 7)
            let wy = year, wm = month, wd = slice[0].d
            for (const c of slice) { if (c.cur) { wd = c.d; break } }
            if (!slice.some(c => c.cur)) {
                if (row === 0) { wm = month === 1 ? 12 : month - 1; wy = month === 1 ? year - 1 : year }
                else           { wm = month === 12 ? 1 : month + 1; wy = month === 12 ? year + 1 : year }
            }
            result.push({ type: 'week', num: isoWeek(wy, wm, wd) })
            for (const c of slice) result.push({ d: c.d, cur: c.cur, firstRow: row === 0 })
        }
        return result
    }

    // Day-of-week headers (8 columns: Wk + Mon…Sun)
    GridLayout {
        Layout.fillWidth: true
        columns: 8
        columnSpacing: 0
        rowSpacing: 0

        Text {
            Layout.fillWidth: true
            text: "Week"
            color: Colors.accent
            font.family: Config.bar.fontFamily
            font.pixelSize: grid.weekFontSize
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Repeater {
            model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            Text {
                Layout.fillWidth: true
                text: modelData
                color: Colors.subtext
                font.family: Config.bar.fontFamily
                font.pixelSize: grid.dowFontSize
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Day cells (week-number sentinels interleaved at col 0)
    GridLayout {
        Layout.fillWidth: true
        columns: 8
        columnSpacing: grid.cellSpacing
        rowSpacing: grid.cellSpacing

        Repeater {
            model: grid.calendarDays()
            delegate: Item {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: grid.cellHeight

                readonly property bool isWeek: modelData.type === 'week'
                readonly property string iso: isWeek ? "" : grid.cellDate(modelData)
                readonly property bool isToday:
                    !isWeek && modelData.cur &&
                    modelData.d === new Date().getDate() &&
                    grid.month === (new Date().getMonth() + 1) &&
                    grid.year === new Date().getFullYear()
                readonly property bool isSelected:
                    grid.showSelection && !isWeek && cell.iso === grid.selectedDate

                // Week number label
                Text {
                    visible: cell.isWeek
                    anchors.centerIn: parent
                    text: cell.isWeek ? cell.modelData.num : ""
                    color: Colors.accent
                    font.family: Config.bar.fontFamily
                    font.pixelSize: grid.weekFontSize
                    font.bold: true
                    opacity: 0.7
                }

                // Today highlight circle / selection ring
                Rectangle {
                    visible: !cell.isWeek
                    anchors.centerIn: parent
                    width: grid.todaySize; height: grid.todaySize
                    radius: grid.todaySize / 3
                    color: cell.isToday ? Colors.accent : "transparent"
                    border.width: cell.isSelected && !cell.isToday ? 2 : 0
                    border.color: Colors.accent
                }

                // Day number
                Text {
                    visible: !cell.isWeek
                    anchors.centerIn: parent
                    text: !cell.isWeek ? cell.modelData.d : ""
                    color: cell.isToday
                        ? Colors.onAccent
                        : cell.modelData.cur
                            ? Colors.text
                            : Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: grid.dayFontSize
                    font.bold: cell.isToday
                }

                // Event dot
                Rectangle {
                    visible: !cell.isWeek && !!grid.eventDates[cell.iso]
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: 5; height: 5; radius: 2.5
                    color: cell.isToday ? Colors.onAccent : Colors.accent
                }

                MouseArea {
                    visible: grid.showSelection && !cell.isWeek
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: grid.dayClicked(cell.iso)
                }
            }
        }
    }
}
