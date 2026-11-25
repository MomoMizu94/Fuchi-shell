import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import "../"
import "../config.js" as Config

Rectangle {
    id: card
    required property bool active
    property var volumes: []
    property string status: "Reading disks…"

    implicitHeight: content.implicitHeight + 2 * Config.gap.lg
    color: Colors.inset
    radius: Config.radius.xl

    function capacity(bytes: real): string {
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        let unit = 0
        while (bytes >= 1024 && unit < units.length - 1) {
            bytes /= 1024
            unit++
        }
        const digits = bytes < 10 && unit > 0 ? 1 : 0
        return bytes.toFixed(digits) + " " + units[unit]
    }

    Process {
        id: usage
        command: ["df", "--local", "--block-size=1", "--output=source,fstype,size,avail,pcent,target"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: output }
        onExited: (code) => {
            const disks = []
            for (const line of output.text.split("\n")) {
                // Anchor on the numeric columns so device names and paths can contain spaces
                const fields = /^(.+?)\s+(\S+)\s+(\d+)\s+(-?\d+)\s+(\d+)%\s+(\/.*)$/.exec(line)
                if (!fields || !(fields[1].startsWith("/dev/") || fields[2] === "zfs"))
                    continue
                disks.push({ mount: fields[6], total: Number(fields[3]),
                             available: Math.max(0, Number(fields[4])), percent: Number(fields[5]) })
            }
            disks.sort((a, b) => a.mount.localeCompare(b.mount))
            card.volumes = disks
            if (code !== 0)
                card.status = disks.length ? "Some disks unavailable" : "Disk usage unavailable"
            else
                card.status = disks.length ? "" : "No mounted local disks"
        }
    }

    Timer {
        running: card.active
        interval: Config.timer.storageRefresh
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!usage.running) usage.running = true
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Config.gap.lg
        spacing: Config.gap.md

        RowLayout {
            spacing: Config.gap.md
            Text {
                text: "DISK USAGE"
                color: Colors.subtext
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.label
                font.bold: true
                font.letterSpacing: 1.5
            }
            Text {
                visible: card.status !== ""
                text: card.status
                color: Colors.subtext
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.sm
            }
        }

        GridLayout {
            Layout.fillWidth: true
            visible: card.volumes.length > 0
            columns: Math.max(1, Math.min(4, Math.floor((content.width + columnSpacing) / (270 + columnSpacing))))
            columnSpacing: Config.gap.xl
            rowSpacing: Config.gap.md
            uniformCellWidths: true

            Repeater {
                model: card.volumes
                delegate: RowLayout {
                    id: volume
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Config.gap.md

                    Rectangle {
                        Layout.preferredWidth: Config.gap.md
                        Layout.minimumHeight: 62
                        Layout.fillHeight: true
                        radius: Config.radius.sm
                        color: Qt.alpha(Colors.subtext, 0.18)

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * Math.min(100, volume.modelData.percent) / 100
                            radius: parent.radius
                            color: volume.modelData.percent >= 95 ? Colors.error : Colors.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.gap.xs
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: volume.modelData.mount.replace(/^\/mnt\//, "/")
                                elide: Text.ElideMiddle
                                color: Colors.text
                                font.family: Settings.fontFamily
                                font.pixelSize: Config.type.base
                                font.bold: true
                                HoverHandler { id: hover }
                                Controls.ToolTip.visible: hover.hovered && (truncated || text !== volume.modelData.mount)
                                Controls.ToolTip.text: volume.modelData.mount
                            }
                            Text {
                                text: volume.modelData.percent + "%"
                                color: Colors.text
                                font.family: Settings.fontFamily
                                font.pixelSize: Config.type.base
                            }
                        }
                        Text {
                            text: card.capacity(volume.modelData.available) + " free of " + card.capacity(volume.modelData.total)
                            color: Colors.subtext
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.label
                        }
                    }
                }
            }
        }
    }
}
