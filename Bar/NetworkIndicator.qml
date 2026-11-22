import QtQuick
import Quickshell.Networking
import "../"

SidebarButton {
    readonly property var wiredDev: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wired) return d
        return null
    }
    readonly property var wifiDev: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wifi) return d
        return null
    }
    readonly property bool wiredUp: wiredDev !== null && wiredDev.connected
    readonly property bool wifiUp: wifiDev !== null && wifiDev.connected

    Accessible.name: wiredUp ? "Wired network" : wifiUp ? "Wi-Fi connected" : "Network disconnected"
    glyph: wiredUp ? "󰈀" : wifiUp ? "󰤨" : Networking.wifiEnabled ? "󰤯" : "󰤭"
    glyphColor: wiredUp || wifiUp ? Colors.accent : Colors.subtext
}
