import QtQuick
import QtQuick.Controls.Basic
import "config.js" as Config

Button {
    id: button
    font.family: Settings.fontFamily
    font.pixelSize: Config.type.sm
    leftPadding: Config.gap.md
    rightPadding: Config.gap.md
    topPadding: Config.gap.sm
    bottomPadding: Config.gap.sm
    opacity: enabled ? 1 : 0.45
    contentItem: Text {
        text: button.text
        font: button.font
        color: Colors.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        implicitHeight: 40
        color: button.down ? Colors.border : button.hovered ? Colors.card : Colors.inset
        radius: Config.radius.lg
        border.width: button.visualFocus ? 2 : 1
        border.color: button.visualFocus ? Colors.accent : Colors.border
    }
}
