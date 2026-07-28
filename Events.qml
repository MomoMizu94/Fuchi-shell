pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Local calendar-event store: ~/.local/state/quickshell/events.json.
// Same persistence mechanism as the Dashboard's to-do list. Kept deliberately
// simple ({date, time, title}); could later be swapped for a khal/CalDAV
// backend behind the same API without touching the UI.
Singleton {
    id: root

    // Bumped on every mutation so bindings over eventsFor() re-evaluate
    // (plain function results carry no change notifications).
    property int revision: 0

    // { "YYYY-MM-DD": true, ... } for the calendar grid's event dots.
    readonly property var eventDates: {
        const _ = revision   // dependency: rebuild the map on every mutation
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

    // Remove the nth event (in eventsFor() order) of the given date.
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
