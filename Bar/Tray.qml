import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../"
import "../config.js" as Config

// System tray icons in the sidebar. Left/middle click activate the item
// directly; right click opens TrayMenu via IPC (see openMenuProc below)
ColumnLayout {
    Layout.alignment: Qt.AlignHCenter
    spacing: Config.gap.sm

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: trayItem
            required property var modelData
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Config.sidebar.trayIconSize
            implicitHeight: Config.sidebar.trayIconSize

            IconImage {
                anchors.fill: parent
                source: trayItem.modelData.icon
            }

            Process { id: openMenuProc; command: ["echo"] }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) trayItem.modelData.activate()
                    else if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate()
                    else if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu) {
                        // Mapped at click time, not in a property binding: the
                        // binding would freeze at its creation-time result
                        // (mapFromItem registers no dependencies), going stale
                        // when the tray column reorders. Bar's window is flush
                        // at the output's top-left, so window-local ==
                        // output-local for the separate-window TrayMenu.
                        const pos = trayItem.QsWindow.contentItem.mapFromItem(trayItem, 0, 0)
                        openMenuProc.command = ["qs", "ipc", "call", "traymenu", "open",
                            trayItem.modelData.id, String(Math.round(pos.y + trayItem.height / 2))]
                        openMenuProc.startDetached()
                    }
                }
            }
        }
    }
}
