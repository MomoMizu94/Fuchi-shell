import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../config.js" as Config

// Sidebar power button. Opens PowerMenu via IPC
Item {
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Config.sidebar.iconSize + Config.gap.md
    Layout.preferredHeight: Config.sidebar.iconSize + Config.gap.md

    Process {
        id: proc
        command: ["qs", "ipc", "call", "powermenu", "toggle"]
    }

    Text {
        anchors.centerIn: parent
        text: "⏻"
        color: Colors.error
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.sidebar.iconSize
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: proc.startDetached()
    }
}
