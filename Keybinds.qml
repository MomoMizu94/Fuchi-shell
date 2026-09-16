pragma ComponentBehavior: Bound
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "config.js" as Config
import "keybinds.js" as Keybinds

// Content for the launcher's keybind mode. AppLauncher owns the window, its
// background, and keyboard focus; this item only loads and displays shortcuts.
Item {
    id: keybinds
    property bool active: false
    property string filter: ""
    property var bindings: []
    property string statusText: ""

    // Reformat the cached bindings as the query changes, without starting a
    // process for each keystroke. The formatter filters before merging ranges.
    readonly property var formatted: Keybinds.buildModel(bindings, filter)
    readonly property var entries: formatted.rows
    readonly property string modLabel: bindings.length ? formatted.modLabel : ""
    readonly property int bindingCount: formatted.bindingCount
    readonly property string emptyText: statusText ||
        (bindings.length ? "No matching keybinds" : "No active keybinds")

    // Entering the mode fetches the current loaded config. Leaving it cancels
    // pending work, but preserves the content during the launcher's close slide.
    onActiveChanged: {
        if (active) {
            bindings = []
            statusText = "Loading keybinds…"
            loadTimeout.restart()
            probe.running = true
        } else {
            loadTimeout.stop()
            probe.running = false
        }
    }
    onEntriesChanged: list.positionViewAtBeginning()

    Process {
        id: probe
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector { id: output }
        onExited: (exitCode, exitStatus) => {
            // A cancelled or timed-out request must not replace the current view.
            if (!keybinds.active || !loadTimeout.running) return
            loadTimeout.stop()
            if (exitCode !== 0 || exitStatus !== 0) {
                keybinds.statusText = "Could not read keybinds. Check that Hyprland is running, then reopen this command."
                return
            }
            try {
                const bindings = JSON.parse(output.text)
                if (!Array.isArray(bindings)) throw new Error("Expected a list of bindings")
                // Validate the response before assigning it to a reactive binding.
                Keybinds.buildModel(bindings)
                keybinds.bindings = bindings
                keybinds.statusText = ""
            } catch (error) {
                console.warn("Could not read Hyprland keybinds:", error)
                keybinds.statusText = "Could not read Hyprland's keybind data. Reopen this command to retry."
            }
        }
    }

    // Process startup failures also reach this timeout, so the loading message
    // cannot remain on screen indefinitely when hyprctl is missing or stuck.
    Timer {
        id: loadTimeout
        interval: 5000
        onTriggered: {
            probe.running = false
            keybinds.statusText = "Hyprland did not respond. Reopen this command to retry."
        }
    }

    // AppLauncher forwards navigation here while retaining focus in its input.
    // Home and End remain available for editing the command text.
    function scrollBy(amount) {
        list.contentY = Math.max(list.originY,
            Math.min(list.contentY + amount, list.originY + Math.max(0, list.contentHeight - list.height)))
    }
    function scrollPage(direction) { scrollBy(direction * list.height) }

    // Anchor the header and list directly. The containing launcher animates its
    // size, and anchors keep the viewport in step with each animation frame.
    RowLayout {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Config.gap.lg
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Config.gap.xs
            Text {
                text: "Keybinds"
                color: Colors.textStrong
                font { family: Config.bar.fontFamily; pixelSize: Config.type.xl; bold: true }
            }
            Text {
                text: keybinds.bindingCount + " active bindings"
                visible: keybinds.bindingCount > 0
                color: Colors.subtext
                font { family: Config.bar.fontFamily; pixelSize: Config.type.sm }
            }
        }
        Text {
            text: keybinds.modLabel
            color: Colors.accent
            font { family: Config.bar.fontFamily; pixelSize: Config.type.md; bold: true }
        }
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top }
        anchors.topMargin: Config.gap.sm
        anchors.bottomMargin: Config.gap.md
        clip: true
        model: keybinds.entries
        boundsBehavior: Flickable.StopAtBounds
        // Wrapped labels and section headings have different heights. Measuring
        // this small list up front avoids shifting scroll limits during navigation.
        cacheBuffer: Math.max(0, contentHeight)
        section.property: "category"
        section.criteria: ViewSection.FullString
        section.delegate: Text {
            required property string section
            width: list.width
            topPadding: Config.gap.lg
            bottomPadding: Config.gap.md
            text: section
            textFormat: Text.PlainText
            color: Colors.accent
            font { family: Config.bar.fontFamily; pixelSize: Config.type.lg; bold: true }
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            focusPolicy: Qt.NoFocus
        }
        // These rows are a reference, not actions. Clicking a shortcut never
        // executes it, and the description wraps instead of hiding long labels.
        delegate: Item {
            id: row
            required property var modelData
            width: list.width - Config.gap.lg
            height: Math.max(shortcut.implicitHeight, actionColumn.implicitHeight) + Config.gap.lg
            RowLayout {
                anchors.fill: parent
                spacing: Config.gap.xl
                Text {
                    id: shortcut
                    Layout.preferredWidth: row.width * 0.43
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Config.gap.sm
                    text: row.modelData.shortcut
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Colors.textStrong
                    font { family: Config.bar.fontFamily; pixelSize: Config.type.base; bold: true }
                }
                ColumnLayout {
                    id: actionColumn
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Config.gap.sm
                    spacing: Config.gap.xs
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.action
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Colors.text
                        font { family: Config.bar.fontFamily; pixelSize: Config.type.base }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: row.modelData.note
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Colors.subtext
                        font { family: Config.bar.fontFamily; pixelSize: Config.type.sm }
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: list
        width: list.width
        visible: keybinds.entries.length === 0
        text: keybinds.emptyText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Colors.text
        font { family: Config.bar.fontFamily; pixelSize: Config.type.base }
    }
    Text {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        text: "Type to filter · ↑ ↓ / PgUp PgDn to scroll · Esc to close"
        wrapMode: Text.WordWrap
        color: Colors.subtext
        font { family: Config.bar.fontFamily; pixelSize: Config.type.sm }
    }
}
