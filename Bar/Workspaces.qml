import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../"
import "../config.js" as Config

ColumnLayout {
    id: root
    Layout.alignment: Qt.AlignHCenter
    spacing: Config.gap.sm

    // Same per-workspace glyphs as hyprland/workspaces.format-icons in
    // ~/.config/waybar/config.jsonc. Falls back to the plain number for any
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

        delegate: Rectangle {
            id: chip
            required property var modelData
            property bool hovered: false
            Layout.alignment: Qt.AlignHCenter
            width: Config.sidebar.workspaceSize
            height: Config.sidebar.workspaceSize
            radius: Config.radius.md
            color: modelData.active ? Colors.accent
                : (chip.hovered ? Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.08) : "transparent")

            Text {
                anchors.centerIn: parent
                text: root.icons[modelData.id] || modelData.id
                color: modelData.active ? Colors.onAccent : Colors.subtext
                font.family: Config.bar.fontFamily
                font.pixelSize: Config.sidebar.iconSize
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: chip.hovered = true
                onExited: chip.hovered = false
                onClicked: Hyprland.dispatch("hl.dsp.focus({workspace = " + chip.modelData.id + "})")
            }
        }
    }
}
