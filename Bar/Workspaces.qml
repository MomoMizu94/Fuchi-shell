import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../"
import "../config.js" as Config

ColumnLayout {
    id: root
    Layout.alignment: Qt.AlignHCenter
    spacing: Config.gap.sm

    // Per-workspace icons; falls back to the plain number for any
    // workspace outside this map.
    readonly property var icons: ({
        1: "󰣇",
        2: "󰶞",
        3: "󰚯",
        4: "󰓓",
        5: "󰓇",
        6: "󰛏",
        7: "󰑋",
        8: "󰙯",
    })

    Repeater {
        model: Hyprland.workspaces

        delegate: SidebarButton {
            id: chip
            required property var modelData
            Accessible.name: "Workspace " + modelData.name
            selected: modelData.active
            glyph: root.icons[modelData.id] || modelData.id
            glyphColor: Colors.subtext
            onClicked: Hyprland.dispatch("hl.dsp.focus({workspace = " + chip.modelData.id + "})")
        }
    }
}
