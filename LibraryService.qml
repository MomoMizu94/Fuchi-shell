import QtQuick
import Quickshell
import Quickshell.Io
import "settings.js" as Paths

Scope {
    id: root
    property bool active: false
    property bool ready: false
    property bool starting: false
    property bool restartWanted: false
    property bool stopping: false
    property int startupTimeoutMs: 5000
    property string stopMessage: ""
    property string folder: Paths.absolutePath(Settings.libraryFolder, Quickshell.env("HOME"))
    property string configuredFolder: ""
    property string error: ""
    property var books: []
    property var warnings: []
    property bool writable: false
    property bool galleryAvailable: false
    property var jobs: []
    property string log: ""
    property var readerSettings: ({})
    property int nextId: 0
    property var pending: []
    property var inFlight: null
    property var progressUpdates: ({})
    property var lastProgress: ({})
    readonly property bool loading: starting || stopping || restartWanted || scanning
    readonly property bool busy: loading
        || inFlight !== null || pending.length > 0 || Object.keys(progressUpdates).length > 0
    property bool scanning: false
    property bool refreshAfterScan: false
    readonly property bool downloading: jobs.some(job => job.status === "running" || job.status === "pending")
    readonly property string stateDirectory: Quickshell.statePath("library")
    readonly property string cacheDirectory: (Quickshell.env("XDG_CACHE_HOME")
        || Quickshell.env("HOME") + "/.cache") + "/quickshell/library"
    property var helperCommand: ["python3",
        decodeURIComponent(Qt.resolvedUrl("scripts/library.py").toString().replace(/^file:\/\//, ""))]
    signal opened(var chapter)
    signal failed(string operation, string message)

    function start() {
        if (helper.running || starting || stopping) return
        configuredFolder = folder
        starting = true
        ready = false
        error = ""
        stopMessage = ""
        startupTimeout.restart()
        helper.running = true
    }

    function request(command) {
        if (restartWanted || stopping) {
            error = "Library is reconnecting. Try again after it finishes loading."
            failed(command.op, error)
            return
        }
        if (command.op === "progress") {
            const old = lastProgress[command.file]
            if (old && old.page === command.page && (command.done === null || command.done === old.done)) return
            const updates = Object.assign({}, progressUpdates)
            if (updates[command.file] && command.done === null) command.done = updates[command.file].done
            updates[command.file] = command
            progressUpdates = updates
            lastProgress[command.file] = {page: command.page, done: command.done}
            if (command.done !== null || !active) flushProgress()
            else if (!progressTimer.running) progressTimer.start()
            return
        }
        flushProgress()
        if (command.op === "open") lastProgress = ({})
        if (command.op === "mark")
            for (const file of command.files) delete lastProgress[file]
        enqueue(command)
    }

    function enqueue(command) {
        if (command.op === "scan") scanning = true
        command.id = ++nextId
        if (command.op === "progress") {
            // Keep the latest page while an earlier request is still running.
            const index = pending.findIndex(item => item.op === "progress" && item.file === command.file)
            if (index >= 0) {
                const previous = pending[index]
                if (command.done === null) command.done = previous.done
                pending[index] = command
                return
            }
        }
        pending = pending.concat([command])
        if (!helper.running) start()
        pump()
    }

    function flushProgress() {
        progressTimer.stop()
        const updates = progressUpdates
        progressUpdates = ({})
        for (const file of Object.keys(updates)) enqueue(updates[file])
    }

    function pump() {
        if (stopping || inFlight !== null) return
        if (restartWanted) {
            if (ready && pending.length && pending[0].op === "progress") {
                inFlight = pending[0]
                pending = pending.slice(1)
                helper.write(JSON.stringify(inFlight) + "\n")
                return
            }
            stopping = true
            ready = false
            if (helper.running) helper.running = false
            else finishHelper("")  // Failed launches do not emit exited.
            return
        }
        if (!ready) return
        if (pending.length > 0) {
            inFlight = pending[0]
            pending = pending.slice(1)
            helper.write(JSON.stringify(inFlight) + "\n")
        } else if (!active) {
            stopping = true
            ready = false
            helper.running = false
        }
    }

    function finishHelper(message) {
        const restart = restartWanted
        const interrupted = (inFlight ? [inFlight] : []).concat(pending)
        startupTimeout.stop()
        ready = false
        starting = false
        scanning = false
        refreshAfterScan = false
        inFlight = null
        pending = []
        restartWanted = false
        stopping = false
        stopMessage = ""
        if (message) error = message
        for (const command of interrupted)
            if (command.op === "progress") delete lastProgress[command.file]
        for (const command of interrupted)
            failed(command.op, message || "Library connection closed. Try again.")
        if (restart && active) Qt.callLater(function() { if (root.active) root.start() })
    }

    function refresh() {
        if (scanning) {
            flushProgress()
            refreshAfterScan = true
            return
        }
        if (!scanning && !pending.some(command => command.op === "scan")
                && (!inFlight || inFlight.op !== "scan"))
            request({op: "scan"})
    }

    function status() {
        if (ready && !inFlight && pending.length === 0) request({op: "status"})
    }

    function apply(update) {
        if (update.scanning !== undefined) scanning = update.scanning
        else if (update.op === "scan") scanning = false
        if (update.warnings !== undefined) warnings = update.warnings
        if (update.covers !== undefined) {
            books = books.map(book => update.covers[book.id] === undefined ? book
                : Object.assign({}, book, {cover: update.covers[book.id]}))
        }
        if (update.books !== undefined) {
            books = update.books
            writable = update.writable
            readerSettings = update.settings
        }
        if (update.jobs !== undefined) {
            const finished = update.jobs.some(job => ["completed", "failed", "cancelled"].includes(job.status)
                && !jobs.some(old => old.id === job.id && old.status === job.status))
            jobs = update.jobs
            log = update.log
            galleryAvailable = update.galleryAvailable
            if (finished) refresh()
        }
        if (update.op === "open") opened(update)
    }

    onFolderChanged: {
        flushProgress()
        lastProgress = ({})
        books = []
        warnings = []
        writable = false
        error = ""
        restartWanted = true
        const interrupted = pending.filter(command => command.op !== "progress")
        pending = pending.filter(command => command.op === "progress")
        for (const command of interrupted)
            failed(command.op, "Library folder changed. Try again in the new folder.")
        if (helper.running || starting || stopping) pump()
        else {
            restartWanted = false
            if (active) start()
        }
    }
    onActiveChanged: {
        if (active) {
            if (stopping) restartWanted = true
            else if (!helper.running) start()
            else { refresh(); status() }
        } else { flushProgress(); pump() }
    }
    Component.onCompleted: if (active) start()

    Timer {
        id: progressTimer
        interval: 1000
        onTriggered: root.flushProgress()
    }

    Timer {
        id: startupTimeout
        interval: root.startupTimeoutMs
        onTriggered: {
            if (!root.starting || root.stopping) return
            root.stopMessage = "Library helper did not start. Check Python 3 and Pillow, then press Refresh to reconnect."
            root.error = root.stopMessage
            root.restartWanted = false
            if (helper.running) {
                root.stopping = true
                helper.running = false
            } else root.finishHelper(root.stopMessage)
        }
    }
    Timer {
        interval: root.downloading ? 1200 : 5000
        running: root.active && root.ready
        repeat: true
        onTriggered: root.status()
    }
    Process {
        id: helper
        command: root.helperCommand.concat(["--root", root.configuredFolder,
            "--state", root.stateDirectory, "--cache", root.cacheDirectory, "serve"])
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                if (root.stopping) return
                try {
                    const update = JSON.parse(data)
                    if (update.event === "scan") {
                        if (!root.restartWanted) {
                            root.apply(update)
                            if (update.error) { root.error = update.error; root.failed("scan", update.error) }
                            if (!root.scanning && root.refreshAfterScan) {
                                root.refreshAfterScan = false
                                root.refresh()
                            }
                        }
                        return
                    }
                    if (update.ready) {
                        root.ready = true
                        root.starting = false
                        startupTimeout.stop()
                        if (root.restartWanted) { root.pump(); return }
                        root.refresh()
                        root.request({op: "status"})
                        root.pump()
                        return
                    }
                    if (!root.inFlight || update.reply !== root.inFlight.id) return
                    const completed = root.inFlight
                    root.inFlight = null
                    if (root.restartWanted) { root.pump(); return }
                    if (update.ok) {
                        if (update.op !== "status") root.error = ""
                        root.apply(update)
                        if (update.op === "mark" || update.op === "trash") root.refresh()
                    } else {
                        if (completed.op === "scan") root.scanning = false
                        if (completed.op === "progress") delete root.lastProgress[completed.file]
                        root.error = update.error
                        root.failed(update.op, update.error)
                    }
                    root.pump()
                } catch (error) {
                    root.error = "Could not read the library helper response: " + error
                    const interrupted = root.inFlight
                    root.inFlight = null
                    if (interrupted && interrupted.op === "scan") root.scanning = false
                    if (interrupted) root.failed(interrupted.op, root.error)
                    root.pump()
                }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("Library helper:", data) }
        onExited: (exitCode, exitStatus) => {
            const message = root.stopMessage || (!root.stopping && root.active
                ? "Library helper stopped. Press Refresh to reconnect." : "")
            root.finishHelper(message)
        }
    }
}
