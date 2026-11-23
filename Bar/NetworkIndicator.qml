import QtQuick
import Quickshell.Networking
import "../"
import "network.js" as Network

SidebarButton {
    readonly property var wiredDev: Network.preferredDevice(Networking.devices.values, DeviceType.Wired)
    readonly property var wifiDev: Network.preferredDevice(Networking.devices.values, DeviceType.Wifi)
    readonly property bool wiredUp: wiredDev !== null && wiredDev.connected
    readonly property bool wifiUp: wifiDev !== null && wifiDev.connected

    Accessible.name: wiredUp ? "Wired network" : wifiUp ? "Wi-Fi connected" : "Network disconnected"
    glyph: wiredUp ? "󰈀" : wifiUp ? "󰤨" : Networking.wifiEnabled ? "󰤯" : "󰤭"
    glyphColor: wiredUp || wifiUp ? Colors.accent : Colors.subtext
}
