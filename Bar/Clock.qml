import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../config.js" as Config

// Sidebar clock. Clicking it opens CalendarMenu via IPC
Item {
    id: root
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: col.implicitWidth
    Layout.preferredHeight: col.implicitHeight

    property string hour: ""
    property string minute: ""
    property string ampm: ""

    Process { id: openMenuProc; command: ["echo"] }

    Timer {
        interval: Config.timer.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Qt.formatTime only resolves "h" as 12-hour when "AP" is present in
            // the same format string — formatting each token separately silently
            // falls back to 24-hour for "h" alone. Format together, then split
            const parts = Qt.formatTime(new Date(), "h|mm|AP").split("|")
            root.hour = parts[0]
            root.minute = parts[1]
            root.ampm = parts[2]
        }
    }

    ColumnLayout {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰃭"
            color: Colors.text
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.sidebar.iconSize
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.hour
            color: Colors.text
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.lg
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.minute
            color: Colors.text
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.lg
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.ampm
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.md
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const pos = root.QsWindow.contentItem.mapFromItem(root, 0, 0)
            // Open CalendarMenu via IPC
            openMenuProc.command = ["qs", "ipc", "call", "calendarmenu", "toggle",
                String(Math.round(pos.y + root.height / 2))]
            openMenuProc.startDetached()
        }
    }
}
