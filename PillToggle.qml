import QtQuick

// 40×20 on/off pill used by the bar menus. Owns no state — the parent binds
// `on` to the real thing and reacts to `toggled`
Rectangle {
    id: pill
    property bool on: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 20
    radius: height / 2
    color: pill.on ? Colors.accent : Colors.inset

    Rectangle {
        width: 14
        height: 14
        radius: 7
        anchors.verticalCenter: parent.verticalCenter
        x: pill.on ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        color: pill.on ? Colors.onAccent : Colors.subtext
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.toggled()
    }
}
