import QtQuick
import "../"

SidebarButton {
    id: root
    required property var service
    Accessible.name: "Updates: " + service.summary
    glyph: service.busy ? "󰑓" : service.count > 0 ? "󰇚"
        : service.complete && !service.hasError ? "󰄬" : "󰏗"
    glyphColor: service.count > 0 ? Colors.accent : Colors.subtext

    Rectangle {
        visible: root.service.hasError
        anchors.right: parent.right
        anchors.top: parent.top
        width: 15
        height: 15
        radius: width / 2
        color: Colors.error
        Text {
            anchors.centerIn: parent
            text: "!"
            color: Colors.bg
            font.bold: true
            font.pixelSize: 12
        }
    }
}
