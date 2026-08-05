import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "config.js" as Config

// Status bar content, living in the left strip that
// FrameReserve reserves and FrameShape paints
PanelWindow {
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

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

        Tray {}
        Clock {}
        BluetoothIndicator {}
        NetworkIndicator {}
        PowerButton {}
    }
}
