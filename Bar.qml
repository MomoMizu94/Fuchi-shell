import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "config.js" as Config

// The actual status bar content, living in the left strip that FrameReserve
// reserves and FrameShape paints. Its own window/own concern, same split as
// FrameReserve (space) vs FrameShape (frame drawing).
PanelWindow {
    color: "transparent"
    // FrameReserve already owns the exclusive zone for this strip — reserving
    // again here would double the gap. Same reasoning as FrameShape.
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
    }

    implicitWidth: Config.frame.thick

    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Config.gap.sm
        spacing: Config.gap.md

        Workspaces {}
    }

    WorkspaceApps {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

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
