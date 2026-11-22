import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "config.js" as Config

// Status bar content, living in the left strip that
// FrameReserve reserves and FrameShape paints
PanelWindow {
    id: bar
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Current tiling layout's dwm label, owned by shell.qml
    property string currentLayout: ""
    required property var updates

    signal trayMenuRequested(string itemId, int centerY)
    signal layoutMenuRequested(int centerY)
    signal calendarMenuRequested(int centerY)
    signal updatesMenuRequested(int centerY)
    signal bluetoothMenuRequested(int centerY)
    signal networkMenuRequested(int centerY)
    signal hostMenuRequested(int centerY)
    signal powerMenuRequested()

    anchors {
        top: true
        bottom: true
        left: true
    }

    implicitWidth: Config.frame.thick

    // Workspace icons
    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Config.gap.sm
        spacing: Config.gap.md

        Workspaces {}
        LayoutIndicator {
            layout: bar.currentLayout
            onClicked: (button, centerY) => bar.layoutMenuRequested(centerY)
        }
    }

    // Apps launched in current workspace
    WorkspaceApps {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    // Rest of the bar: tray, clock, bluetooth etc.
    ColumnLayout {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Config.gap.sm
        spacing: Config.gap.md

        Tray {
            id: tray
            onMenuRequested: (itemId, centerY) => bar.trayMenuRequested(itemId, centerY)
        }
        Clock {
            Layout.topMargin: tray.visible ? Config.gap.sm : 0
            Layout.bottomMargin: Config.gap.sm
            onClicked: (button, centerY) => bar.calendarMenuRequested(centerY)
        }
        UpdateIndicator {
            service: bar.updates
            onClicked: (button, centerY) => bar.updatesMenuRequested(centerY)
        }
        BluetoothIndicator {
            onClicked: (button, centerY) => bar.bluetoothMenuRequested(centerY)
        }
        NetworkIndicator {
            onClicked: (button, centerY) => bar.networkMenuRequested(centerY)
        }
        HostIndicator {
            onClicked: (button, centerY) => bar.hostMenuRequested(centerY)
        }
        PowerButton {
            onClicked: bar.powerMenuRequested()
        }
    }
}
