import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../"
import "../config.js" as Config

ColumnLayout {
    id: tray
    signal menuRequested(string itemId, int centerY)
    Layout.alignment: Qt.AlignHCenter
    spacing: Config.gap.xs
    visible: items.count > 0

    Repeater {
        id: items
        model: SystemTray.items

        delegate: SidebarButton {
            id: trayItem
            required property var modelData
            Accessible.name: modelData.title || modelData.id
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: (button, centerY) => {
                if (button === Qt.LeftButton) modelData.activate()
                else if (button === Qt.MiddleButton) modelData.secondaryActivate()
                else if (button === Qt.RightButton && modelData.hasMenu)
                    tray.menuRequested(modelData.id, centerY)
            }

            IconImage {
                anchors.centerIn: parent
                width: Config.sidebar.trayIconSize
                height: width
                source: trayItem.modelData.icon
            }
        }
    }
}
