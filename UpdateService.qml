pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "config.js" as Config

Scope {
    id: root
    property bool automatic: true
    property int intervalMs: Config.updates.intervalMs
    property real timeoutSeconds: Config.updates.timeoutSeconds
    property var helperCommand: ["python3", Quickshell.shellPath("scripts/check-updates.py")]
    property alias repositories: repositories
    property alias aur: aur
    property double lastAttempt: 0
    property double now: Date.now()
    readonly property bool busy: repositories.checking || aur.checking
    readonly property bool hasError: repositories.error !== "" || aur.error !== ""
    readonly property bool complete: repositories.lastSuccess > 0 && aur.lastSuccess > 0
    readonly property int count: repositories.packages.length + aur.packages.length
    readonly property string summary: busy ? "Checking for updates…"
        : hasError ? "Update check incomplete"
        : !complete ? "Not checked yet"
        : count === 0 ? "Up to date"
        : count + (count === 1 ? " update available" : " updates available")

    function refresh() {
        if (busy) return
        lastAttempt = Date.now()
        repositories.refresh()
        aur.refresh()
    }

    function checkedText(timestamp) {
        if (!timestamp) return "Not checked yet"
        const minutes = Math.max(0, Math.floor((now - timestamp) / 60000))
        if (minutes === 0) return "Checked just now"
        if (minutes < 60) return "Checked " + minutes + (minutes === 1 ? " minute ago" : " minutes ago")
        return "Checked " + Qt.formatDateTime(new Date(timestamp), "MMM d, HH:mm")
    }

    Component.onCompleted: if (automatic) refresh()
    // Wall-clock comparison also catches an overdue check after suspend.
    Timer {
        interval: Math.max(100, Math.min(30000, root.intervalMs))
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now()
            if (root.automatic && root.now - root.lastAttempt >= root.intervalMs) root.refresh()
        }
    }

    component SourceCheck: Scope {
        id: sourceCheck
        required property string source
        property var packages: []
        property double lastSuccess: 0
        property string error: ""
        property bool checking: false
        property string response: ""

        function refresh() {
            if (checking || process.running) return
            checking = true
            response = ""
            watchdog.interval = 5000
            watchdog.restart()
            process.running = true
        }

        function finish(code) {
            if (!checking) return
            watchdog.stop()
            try {
                if (code !== 0) throw new Error("Update helper exited with code " + code + ". Check Python 3 is installed.")
                const result = JSON.parse(response)
                if (result.ok !== true) throw new Error(result.error || "Update check failed")
                if (!Array.isArray(result.packages)) throw new Error("Invalid package list from update helper")
                for (const item of result.packages) {
                    if (!item || typeof item.name !== "string" || typeof item.installed !== "string"
                            || typeof item.available !== "string") throw new Error("Invalid package entry from update helper")
                }
                packages = result.packages
                lastSuccess = Date.now()
                root.now = lastSuccess
                error = ""
            } catch (failure) {
                // Preserve the last successful result; an error is not an empty list.
                error = String(failure.message || failure)
            }
            checking = false
        }

        Process {
            id: process
            command: root.helperCommand.concat([sourceCheck.source, "--timeout", String(root.timeoutSeconds)])
            stdout: StdioCollector { onStreamFinished: sourceCheck.response = text }
            stderr: StdioCollector {}
            onStarted: {
                watchdog.interval = (root.timeoutSeconds + 5) * 1000
                watchdog.restart()
            }
            onExited: (exitCode, exitStatus) => sourceCheck.finish(exitCode)
        }

        // Covers a helper that cannot start or fails before its own timeout.
        Timer {
            id: watchdog
            interval: (root.timeoutSeconds + 5) * 1000
            onTriggered: {
                sourceCheck.error = "Update helper did not finish. Check Python 3 is installed, then try Check now."
                sourceCheck.checking = false
                process.running = false
            }
        }
    }

    SourceCheck { id: repositories; source: "repositories" }
    SourceCheck { id: aur; source: "aur" }
}
