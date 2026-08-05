pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Local calendar-event store: ~/.local/state/quickshell/events.json.
// Same persistence mechanism as the Dashboard's to-do list. Kept deliberately
// simple ({date, time, title}); could later be swapped for a khal/CalDAV
// backend behind the same API without touching the UI
Singleton {
    id: root

    // Bumped on every mutation so bindings over eventsFor() re-evaluate
    // (plain function results carry no change notifications)
    property int revision: 0

    // Shared date constants/helpers — used by both CalendarTab.qml and
    // Bar/CalendarMenu.qml so the two calendar UIs can't drift out of sync
    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function isoToday() {
        const n = new Date()
        return n.getFullYear() + "-" + String(n.getMonth() + 1).padStart(2, "0")
            + "-" + String(n.getDate()).padStart(2, "0")
    }

    // "Sun 5 August" style heading for an ISO ("YYYY-MM-DD") date string
    function headingFor(dateIso) {
        const p = dateIso.split("-")
        const d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
        return dayNames[d.getDay()] + " " + d.getDate() + " " + monthNames[d.getMonth()]
    }

    // { "YYYY-MM-DD": true, ... } for the calendar grid's event dots
    readonly property var eventDates: {
        // dependency: rebuild the map on every mutation
        const _ = revision
        const map = {}
        for (const e of eventData.events) map[e.date] = true
        return map
    }

    function eventsFor(date) {
        return eventData.events
            .filter(e => e.date === date)
            .sort((a, b) => (a.time || "99:99") < (b.time || "99:99") ? -1 : 1)
    }

    function add(date, time, title) {
        if (!date || !title) return
        eventData.events = eventData.events.concat([{ date: date, time: time, title: title }])
        eventFile.writeAdapter()
        revision++
    }

    // Remove the nth event (in eventsFor() order) of the given date
    function removeAt(date, index) {
        const dayEvents = eventsFor(date)
        if (index < 0 || index >= dayEvents.length) return
        const victim = dayEvents[index]
        const all = eventData.events.slice()
        const i = all.findIndex(e => e.date === victim.date && e.time === victim.time && e.title === victim.title)
        if (i !== -1) all.splice(i, 1)
        eventData.events = all
        eventFile.writeAdapter()
        revision++
    }

    FileView {
        id: eventFile
        path: Quickshell.statePath("events.json")
        watchChanges: false
        JsonAdapter {
            id: eventData
            property var events: []
        }
        onLoaded: root.revision++
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter()
        }
    }
}
