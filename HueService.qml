import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool active: false
    property bool ready: false
    property var state: ({})
    property string error: ""
    property int nextId: 0
    property int pendingId: 0
    property bool starting: false
    readonly property bool busy: starting || pendingId !== 0 || !!state.busy
    readonly property bool connected: active && ready && !!state.connected
    property var command: ["sh", Quickshell.shellPath("scripts/hue.sh"),
        "--state", Quickshell.statePath("hue.json"), "serve"]

    function start() {
        if (helper.running) return
        ready = false
        starting = true
        error = ""
        helper.running = true
        startupTimeout.restart()
    }

    function setActive() {
        // Lifecycle requests must follow any operation already in progress.
        helper.write(JSON.stringify({op: "active", value: active}) + "\n")
    }

    function send(command) {
        if (!active || !ready || busy || !helper.running) return
        pendingId = ++nextId
        command.id = pendingId
        error = ""
        helper.write(JSON.stringify(command) + "\n")
    }

    onActiveChanged: {
        if (active && !helper.running) start()
        else if (ready) setActive()
    }
    Component.onCompleted: if (active) start()

    Timer {
        id: startupTimeout
        interval: 5000
        onTriggered: {
            root.starting = false
            if (!root.ready) {
                if (!root.error) root.error = "Could not start the Hue helper. Check the Hue Go setup in README."
                helper.running = false
            }
        }
    }
    Process {
        id: helper
        command: root.command
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const update = JSON.parse(data)
                    const first = !root.ready && update.ready
                    root.state = update
                    root.ready = !!update.ready
                    root.starting = false
                    startupTimeout.stop()
                    root.error = update.error || ""
                    if (update.reply === root.pendingId) root.pendingId = 0
                    if (first) root.setActive()
                } catch (error) {
                    root.error = "Could not read the Hue helper response: " + error
                    root.pendingId = 0
                }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("Hue:", data) }
        onExited: {
            root.ready = false
            root.starting = false
            root.pendingId = 0
            root.state = ({})
            startupTimeout.stop()
            if (!root.error) root.error = "Hue helper stopped. Retry to reconnect."
        }
    }
}
