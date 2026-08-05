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

    // DesktopEntries finishes scanning .desktop files asynchronously, after
    // this component is created — heuristicLookup() is a plain method call
    // with no notify signal to hook, so a delegate that calls it before the
    // scan finishes gets null permanently with no way to know to retry.
    // Bump a generation counter a handful of times over ~3s (comfortably
    // past the scan time observed during testing) and have each delegate's
    // `entry` binding read it, so they all recompute as entries come online.
    property int entriesGeneration: 0
    Timer {
        interval: 400
        running: true
        repeat: true
        property int attempts: 0
        onTriggered: {
            root.entriesGeneration++
            attempts++
            if (attempts >= 8) stop()
        }
    }

    Repeater {
        model: Hyprland.toplevels

        delegate: Item {
            required property var modelData
            // Native Wayland windows expose appId directly; XWayland/X11
            // windows don't -> fallback to class name
            readonly property string appId: (modelData.wayland ? modelData.wayland.appId
                : (modelData.lastIpcObject ? modelData.lastIpcObject.class : "")) || ""
            // entriesGeneration read here is what forces a re-lookup once the
            // async .desktop scan has data
            readonly property var entry: (appId && root.entriesGeneration >= 0) ? DesktopEntries.heuristicLookup(appId) : null

            // Only show windows on the currently workspace
            visible: modelData.workspace && modelData.workspace.active
            width: Config.sidebar.workspaceAppIconSize + Config.gap.sm
            height: width

            // Tinted background for the focused window
            Rectangle {
                anchors.fill: parent
                radius: Config.radius.md
                color: modelData.activated ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.30) : "transparent"
            }

            IconImage {
                anchors.centerIn: parent
                width: Config.sidebar.workspaceAppIconSize
                height: Config.sidebar.workspaceAppIconSize
                // Desktop-entry icon when the lookup succeeded, otherwise a
                // best-effort guess straight from the raw appId
                source: entry ? Quickshell.iconPath(entry.icon, true)
                    : (appId ? Quickshell.iconPath(appId, true) : "")
            }
        }
    }
}
