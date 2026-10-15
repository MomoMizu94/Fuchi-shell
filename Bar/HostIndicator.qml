import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../config.js" as Config

Item {
    id: root
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Config.sidebar.iconSize + Config.gap.md
    Layout.preferredHeight: Config.sidebar.iconSize + Config.gap.md
    Accessible.role: Accessible.Button
    Accessible.name: "Open hosts"

    Process { id: openMenuProc }

    Rectangle {
        anchors.fill: parent
        radius: Config.radius.md
        color: mouse.containsMouse ? Colors.card : "transparent"
    }

    Text {
        anchors.centerIn: parent
        text: "󰆍"
        color: Colors.accent
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.sidebar.iconSize
        Accessible.ignored: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const pos = root.QsWindow.contentItem.mapFromItem(root, 0, 0)
            openMenuProc.command = ["qs", "ipc", "call", "hostmenu", "toggle",
                String(Math.round(pos.y + root.height / 2))]
            openMenuProc.startDetached()
        }
    }
}
