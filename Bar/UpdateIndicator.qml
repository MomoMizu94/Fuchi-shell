import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../config.js" as Config

Item {
    id: root
    required property var service
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Config.sidebar.iconSize + Config.gap.md
    Layout.preferredHeight: Config.sidebar.iconSize + Config.gap.md
    Accessible.role: Accessible.Button
    Accessible.name: "Updates: " + service.summary
    Accessible.onPressAction: openMenu()

    function openMenu() {
        const position = root.QsWindow.contentItem.mapFromItem(root, 0, 0)
        openMenuProc.command = ["qs", "ipc", "call", "updatesmenu", "toggle",
            String(Math.round(position.y + root.height / 2))]
        openMenuProc.startDetached()
    }

    Process { id: openMenuProc }

    Rectangle {
        anchors.fill: parent
        radius: Config.radius.md
        color: mouse.containsMouse ? Colors.card : "transparent"
    }
    Text {
        anchors.centerIn: parent
        text: root.service.busy ? "󰑓" : root.service.count > 0 ? "󰇚"
            : root.service.complete && !root.service.hasError ? "󰄬" : "󰏗"
        color: root.service.count > 0 ? Colors.accent : Colors.subtext
        font.family: Settings.fontFamily
        font.pixelSize: Config.sidebar.iconSize
        Accessible.ignored: true
    }
    Rectangle {
        visible: root.service.hasError
        anchors.right: parent.right
        anchors.top: parent.top
        width: 15
        height: 15
        radius: width / 2
        color: Colors.error
        Text {
            anchors.centerIn: parent
            text: "!"
            color: Colors.bg
            font.bold: true
            font.pixelSize: 12
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openMenu()
    }
}
