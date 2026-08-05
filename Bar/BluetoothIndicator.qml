import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../"
import "../config.js" as Config

// Sidebar Bluetooth icon, accented when the default adapter is powered on.
// Clicking it opens BluetoothMenu via IPC (see openMenuProc below)
Item {
    id: root
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Config.sidebar.trayIconSize + Config.gap.sm
    Layout.preferredHeight: Config.sidebar.trayIconSize + Config.gap.sm

    readonly property bool enabled: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled

    Process { id: openMenuProc; command: ["echo"] }

    Text {
        anchors.centerIn: parent
        text: "󰂯"
        color: root.enabled ? Colors.accent : Colors.subtext
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.sidebar.iconSize
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // Mapped at click time, not in a property binding: contentItem is
            // constant (null until the window maps, no re-notify) and
            // mapFromItem registers no dependencies, so a binding would stay
            // frozen at its first result forever. Bar's window sits flush at
            // the output's top-left, so window-local == output-local for the
            // (separate-window) BluetoothMenu
            const pos = root.QsWindow.contentItem.mapFromItem(root, 0, 0)
            openMenuProc.command = ["qs", "ipc", "call", "bluetoothmenu", "toggle",
                String(Math.round(pos.y + root.height / 2))]
            openMenuProc.startDetached()
        }
    }
}
