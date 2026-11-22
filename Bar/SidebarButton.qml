import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

Rectangle {
    id: control
    property string glyph: ""
    property color glyphColor: Colors.text
    property int glyphSize: Config.sidebar.iconSize
    property bool selected: false
    property alias acceptedButtons: pointer.acceptedButtons
    signal clicked(int button, int centerY)

    implicitWidth: Config.sidebar.targetSize
    implicitHeight: Config.sidebar.targetSize
    Layout.alignment: Qt.AlignHCenter
    radius: Config.radius.md
    color: selected ? Colors.accent : pointer.containsMouse
        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.30) : "transparent"
    border.width: pointer.containsMouse ? 1 : 0
    border.color: selected ? Colors.textStrong : Colors.accent

    Accessible.role: Accessible.Button
    Accessible.onPressAction: control.activate(Qt.LeftButton)

    function activate(button) {
        // Read the center at click time because the tray can reorder
        const center = mapToItem(null, width / 2, height / 2)
        clicked(button, Math.round(center.y))
    }

    Text {
        visible: control.glyph !== ""
        anchors.centerIn: parent
        text: control.glyph
        color: control.selected ? Colors.contrastText : control.glyphColor
        font.family: Settings.fontFamily
        font.pixelSize: control.glyphSize
        Accessible.ignored: true
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => control.activate(mouse.button)
    }
}
