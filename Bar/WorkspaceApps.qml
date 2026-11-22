import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../"
import "../config.js" as Config

// Lists every app open on the currently active workspace,
// with the focused window highlighted
Column {
    id: root
    spacing: Config.gap.sm

    Repeater {
        model: Hyprland.toplevels

        delegate: Item {
            id: app
            required property var modelData
            // Native Wayland windows expose appId directly; XWayland/X11
            // windows don't -> fallback to class name
            readonly property string appId: (modelData.wayland ? modelData.wayland.appId
                : (modelData.lastIpcObject ? modelData.lastIpcObject.class : "")) || ""
            property var entry: null
            readonly property string windowTitle: modelData.title || (entry ? entry.name : "") || appId

            function refreshEntry() {
                const desktopId = appId.startsWith("fuchi-ssh-") ? "kitty" : appId
                entry = desktopId ? DesktopEntries.heuristicLookup(desktopId) : null
            }

            onAppIdChanged: Qt.callLater(refreshEntry)
            Connections {
                target: DesktopEntries
                function onApplicationsChanged() { Qt.callLater(app.refreshEntry) }
            }

            visible: modelData.workspace && modelData.workspace.active
            width: Config.sidebar.workspaceAppIconSize + Config.gap.sm
            height: width

            // Tinted background for the focused window
            Rectangle {
                anchors.fill: parent
                radius: Config.radius.md
                color: modelData.activated ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.30) : "transparent"
            }

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (hovered) titleDelay.restart()
                    else {
                        titleDelay.stop()
                        titlePopup.visible = false
                    }
                }
            }
            Timer {
                id: titleDelay
                interval: 400
                onTriggered: titlePopup.visible = hover.hovered && app.visible && app.windowTitle !== ""
            }
            onVisibleChanged: if (!visible) titlePopup.visible = false

            PopupWindow {
                id: titlePopup
                visible: false
                grabFocus: false
                anchor.item: app
                anchor.edges: Edges.Right
                anchor.gravity: Edges.Right
                anchor.margins.right: Config.gap.sm
                implicitWidth: Math.min(420, titleText.implicitWidth + Config.gap.md * 2)
                implicitHeight: titleText.implicitHeight + Config.gap.sm * 2
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    radius: Config.radius.md
                    color: Colors.surface
                    border.color: Colors.border
                    Text {
                        id: titleText
                        anchors.fill: parent
                        anchors.leftMargin: Config.gap.md
                        anchors.rightMargin: Config.gap.md
                        verticalAlignment: Text.AlignVCenter
                        text: app.windowTitle
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: Settings.fontFamily
                        font.pixelSize: Config.type.sm
                        color: Colors.text
                    }
                }
            }

            IconImage {
                anchors.centerIn: parent
                width: Config.sidebar.workspaceAppIconSize
                height: Config.sidebar.workspaceAppIconSize
                // Desktop-entry icon when the lookup succeeded, otherwise a
                // best-effort guess straight from the raw appId
                source: app.entry && app.entry.icon ? Quickshell.iconPath(app.entry.icon, true)
                    : (app.appId ? Quickshell.iconPath(app.appId, true) : "")
            }
        }
    }
}
