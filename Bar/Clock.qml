import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

SidebarButton {
    id: root
    implicitHeight: col.implicitHeight + Config.gap.sm
    Accessible.name: "Calendar, " + hour + ":" + minute + " " + ampm

    property string hour: ""
    property string minute: ""
    property string ampm: ""

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
        anchors.centerIn: parent
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰃭"
            color: Colors.text
            font.family: Settings.fontFamily
            font.pixelSize: Config.sidebar.iconSize
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.hour
            color: Colors.text
            font.family: Settings.fontFamily
            font.pixelSize: Config.type.lg
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.minute
            color: Colors.text
            font.family: Settings.fontFamily
            font.pixelSize: Config.type.lg
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.ampm
            color: Colors.subtext
            font.family: Settings.fontFamily
            font.pixelSize: Config.type.md
        }
    }
}
