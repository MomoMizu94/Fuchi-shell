import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../"
import "../config.js" as Config

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

            // Bar's own PanelWindow is flush against the output's top-left
            // corner (anchored top+bottom+left), so this window-local point
            // doubles as the output-local position TrayMenu needs to line up
            // with the icon from its own (separate, full-screen) window.
            readonly property point windowPos: trayItem.QsWindow.contentItem.mapFromItem(trayItem, 0, 0)

            IconImage {
                anchors.fill: parent
                source: trayItem.modelData.icon
            }

            Process {
                id: openMenuProc
                command: ["qs", "ipc", "call", "traymenu", "open", trayItem.modelData.id,
                    String(Math.round(trayItem.windowPos.y + trayItem.height / 2))]
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) trayItem.modelData.activate()
                    else if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate()
                    else if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu) openMenuProc.startDetached()
                }
            }
        }
    }
}
