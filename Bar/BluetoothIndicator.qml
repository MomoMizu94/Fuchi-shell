import QtQuick
import Quickshell.Bluetooth
import "../"

SidebarButton {
    readonly property bool powered: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    Accessible.name: powered ? "Bluetooth on" : "Bluetooth off"
    glyph: "󰂯"
    glyphColor: powered ? Colors.accent : Colors.subtext
}
