import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../config.js" as Config

// Current tiling layout indicator. The label is owned by
// shell.qml (hyprland config pushes it there on every change) and handed down
// through Bar.qml. Clicking opens LayoutMenu via IPC, like the other indicators
Item {
    id: root
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: Config.frame.thick - Config.gap.sm * 2
    Layout.preferredHeight: Config.sidebar.workspaceSize

    // dwm label ("tile", "bstack", ...), set by Bar.qml
    property string layout: ""

    readonly property string glyph: {
        for (const l of Config.layouts)
            if (l.label === root.layout)
                return Config.sidebar.useNerdLayoutGlyphs ? l.nerd : l.ascii
        return ""
    }

    Process { id: openMenuProc; command: ["echo"] }

    Rectangle {
        id: chip
        anchors.fill: parent
        radius: Config.radius.md
        color: mouse.containsMouse
            ? Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.08)
            : "transparent"

        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: Colors.text
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.sidebar.useNerdLayoutGlyphs
                ? Config.sidebar.iconSize
                : Config.sidebar.layoutGlyphSize
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const pos = root.QsWindow.contentItem.mapFromItem(root, 0, 0)
            // Opens LayoutMenu
            openMenuProc.command = ["qs", "ipc", "call", "layoutmenu", "toggle",
                String(Math.round(pos.y + root.height / 2))]
            openMenuProc.startDetached()
        }
    }
}
