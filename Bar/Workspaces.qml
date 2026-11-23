import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"
import "../config.js" as Config

ColumnLayout {
    id: root
    Layout.alignment: Qt.AlignHCenter
    spacing: Config.gap.sm

    // Per-workspace icons; falls back to the plain number for any
    // workspace outside this map.
    readonly property var icons: ({
        1: "󰣇",
        2: "󰶞",
        3: "󰚯",
        4: "󰓓",
        5: "󰓇",
        6: "󰛏",
        7: "󰑋",
        8: "󰙯",
    })

    WorkspacePreview { id: preview }
    Timer {
        interval: 100
        running: !!preview.chip && !preview.chip.hovered
        onTriggered: preview.chip = null
    }

    Repeater {
        model: Hyprland.workspaces

        delegate: SidebarButton {
            id: chip
            required property var modelData
            property string snapshot: ""
            property bool captureFailed: false
            property bool missingTool: false
            readonly property string output: modelData.monitor?.name || ""
            readonly property bool canCapture: modelData.active && output !== "" && !preview.chip && !missingTool

            function takeSnapshot() {
                if (!canCapture || capture.running) return
                capture.acceptFrame = true
                capture.command = ["python3", Quickshell.shellDir + "/scripts/workspace-preview.py",
                    output, String(modelData.id), String(preview.thumbnailWidth)]
                capture.running = true
            }

            // A switch away and back can happen while grim is still reading the output
            onCanCaptureChanged: if (!canCapture) capture.acceptFrame = false
            onOutputChanged: capture.acceptFrame = false

            Timer {
                interval: 600
                running: chip.canCapture
                onTriggered: chip.takeSnapshot()
            }
            Timer {
                interval: 8000
                running: chip.canCapture
                repeat: true
                onTriggered: chip.takeSnapshot()
            }
            Process {
                id: capture
                property bool acceptFrame: false
                stdout: StdioCollector { id: frame }
                onExited: code => {
                    if (!acceptFrame || !chip.canCapture) return
                    if (code === 0 && frame.text) {
                        chip.snapshot = frame.text.trim()
                        chip.captureFailed = false
                    } else if (code !== 0) {
                        chip.captureFailed = true
                        chip.missingTool = code === 2
                    }
                }
            }
            Rectangle {
                id: urgencyDot
                objectName: "workspaceUrgencyDot"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                width: 6
                height: width
                radius: width / 2
                visible: !chip.selected && !!chip.modelData.urgent
                color: Colors.warn
                Accessible.ignored: true
            }
            Accessible.name: "Workspace " + modelData.name + (urgencyDot.visible ? ", needs attention" : "")
            selected: modelData.active
            glyph: root.icons[modelData.id] || modelData.id
            glyphColor: Colors.subtext
            onClicked: {
                delay.stop()
                preview.chip = null
                Hyprland.dispatch("hl.dsp.focus({workspace = " + chip.modelData.id + "})")
            }
            onHoveredChanged: {
                if (!hovered) delay.stop()
                else if (preview.chip && (snapshot || !modelData.active)) preview.chip = chip
                else {
                    preview.chip = null
                    if (!snapshot) takeSnapshot()
                    delay.restart()
                }
            }
            Timer {
                id: delay
                interval: 400
                onTriggered: {
                    if (!chip.hovered) return
                    if (capture.running && !chip.snapshot) delay.restart()
                    else preview.chip = chip
                }
            }
        }
    }
}
