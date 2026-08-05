import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../"
import "../config.js" as Config

// Sidebar network icon: shows wired/Wi-Fi/disconnected state at a glance
// Clicking it opens NetworkMenu via IPC
Item {
    id: root
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Config.sidebar.trayIconSize + Config.gap.sm
    Layout.preferredHeight: Config.sidebar.trayIconSize + Config.gap.sm

    readonly property var wiredDev: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wired) return d
        return null
    }
    readonly property var wifiDev: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wifi) return d
        return null
    }
    readonly property bool wiredUp: wiredDev !== null && wiredDev.connected
    readonly property bool wifiUp: wifiDev !== null && wifiDev.connected

    Process { id: openMenuProc; command: ["echo"] }

    Text {
        anchors.centerIn: parent
        text: root.wiredUp ? "󰈀"
            : root.wifiUp ? "󰤨"
            : Networking.wifiEnabled ? "󰤯"
            : "󰤭"
        color: root.wiredUp || root.wifiUp ? Colors.accent : Colors.subtext
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.sidebar.iconSize
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const pos = root.QsWindow.contentItem.mapFromItem(root, 0, 0)
            // Open NetworkMenu
            openMenuProc.command = ["qs", "ipc", "call", "networkmenu", "toggle",
                String(Math.round(pos.y + root.height / 2))]
            openMenuProc.startDetached()
        }
    }
}
