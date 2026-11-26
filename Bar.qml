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
    property string pickedColor: ""
    required property var updates

    signal trayMenuRequested(string itemId, int centerY)
    signal layoutMenuRequested(int centerY)
    signal calendarMenuRequested(int centerY)
    signal clipboardRequested(int centerY)
    signal colorRequested(bool reuse)
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

    Flickable {
        id: barView
        anchors.fill: parent
        contentWidth: width
        // Keep one app reachable when the two control groups exceed the screen height
        contentHeight: Math.max(height, upperControls.implicitHeight + lowerControls.implicitHeight
            + 2 * (Config.gap.sm + Config.gap.md) + Math.min(apps.implicitHeight, Config.sidebar.targetSize))
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollWheel { view: barView }

        // Workspace icons
        ColumnLayout {
            id: upperControls
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

        Flickable {
            id: appView
            readonly property real firstY: upperControls.y + upperControls.height + Config.gap.md
            readonly property real lastY: lowerControls.y - Config.gap.md
            width: bar.width
            height: Math.min(apps.implicitHeight, Math.max(0, lastY - firstY))
            y: Math.max(firstY, Math.min((bar.height - height) / 2, lastY - height))
            contentWidth: width
            contentHeight: apps.implicitHeight
            interactive: contentHeight > height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollWheel { view: appView }

            WorkspaceApps {
                id: apps
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // Rest of the bar: tray, clock, bluetooth etc.
        ColumnLayout {
            id: lowerControls
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Config.gap.sm
            spacing: Config.gap.md

            Tray {
                onMenuRequested: (itemId, centerY) => bar.trayMenuRequested(itemId, centerY)
            }
            Clock {
                Layout.topMargin: Config.gap.sm
                Layout.bottomMargin: Config.gap.sm
                onClicked: (button, centerY) => bar.calendarMenuRequested(centerY)
            }
            SidebarButton {
                glyph: "󰅌"
                glyphColor: Colors.accent
                Accessible.name: "Clipboard history"
                onClicked: (button, centerY) => bar.clipboardRequested(centerY)
            }
            SidebarButton {
                glyph: "󰈋"
                glyphColor: Colors.accent
                Accessible.name: "Pick a screen color"
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (button, centerY) => bar.colorRequested(button === Qt.RightButton)
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 11
                    height: width
                    radius: width / 2
                    visible: bar.pickedColor !== ""
                    color: bar.pickedColor || "transparent"
                    border.color: Colors.text
                }
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
}
