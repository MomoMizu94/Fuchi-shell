import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"
import "../config.js" as Config

// Tiling layout picker, sliding out from the sidebar next to the layout
// indicator that was clicked
PanelWindow {
    id: layoutMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    property real targetY: 0
    // Active layout's dwm label, so the matching row can be marked
    property string current: ""
    visible: open || closing
    onOpenChanged: closing = !open

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    // Ignore (not Normal) keeps this window's coordinates lined up with Bar's:
    // both windows then span the full screen, so the icon y-position Bar
    // hands over lands in the right spot here too
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Process { id: applyProc; command: ["echo"] }

    MouseArea {
        anchors.fill: parent
        onClicked: layoutMenu.closeRequested()
    }

    Item {
        id: panel
        width: Config.layoutMenu.width
        height: column.implicitHeight + Config.layoutMenu.padding * 2

        anchors.left: parent.left
        anchors.top: parent.top
        // Center on the clicked indicator's y, clamped so the panel — plus
        // its corner fillets — never runs off the top/bottom of the frame
        anchors.topMargin: Math.max(
            Config.frame.thin + Config.radius.fillet,
            Math.min(layoutMenu.targetY - height / 2, parent.height - height - Config.frame.thin - Config.radius.fillet)
        )
        // Open: docked flush against the sidebar's inner edge; closed: fully
        // off-screen left. The model is static, so unlike TrayMenu there is
        // nothing to wait for before sliding in
        anchors.leftMargin: layoutMenu.open ? Config.frame.thick : -width
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !layoutMenu.open) layoutMenu.closing = false
            }
        }

        // Swallows clicks inside the panel so they don't fall through to the
        // full-screen close catcher behind it
        MouseArea { anchors.fill: parent }

        // Curves the panel's left corners inward so they blend into the
        // sidebar's edge
        CornerFillet {
            anchors.left: parent.left
            anchors.bottom: parent.top
            solidCorner: "bottomLeft"
        }
        CornerFillet {
            anchors.left: parent.left
            anchors.top: parent.bottom
            solidCorner: "topLeft"
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: 0
            bottomLeftRadius: 0
            topRightRadius: Config.radius.hero
            bottomRightRadius: Config.radius.hero
            color: Colors.surface
            clip: true

            ColumnLayout {
                id: column
                anchors.fill: parent
                anchors.margins: Config.layoutMenu.padding
                spacing: Config.layoutMenu.gap

                Repeater {
                    model: Config.layouts

                    delegate: Item {
                        id: layoutRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Config.layoutMenu.rowHeight

                        readonly property bool active: layoutRow.modelData.label === layoutMenu.current

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: rowHover.hovered ? Colors.card : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm

                                // Fixed width so the names line up in a column
                                // regardless of glyph set
                                Text {
                                    Layout.preferredWidth: Config.sidebar.layoutGlyphSize * 2
                                    text: Config.sidebar.useNerdLayoutGlyphs
                                        ? layoutRow.modelData.nerd
                                        : layoutRow.modelData.ascii
                                    color: layoutRow.active ? Colors.accent : Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.sidebar.layoutGlyphSize
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: layoutRow.modelData.label
                                    color: layoutRow.active ? Colors.accent : Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: layoutRow.modelData.key
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                }

                                // Radio marker indicator for active layout
                                Text {
                                    Layout.preferredWidth: Config.type.sm
                                    horizontalAlignment: Text.AlignRight
                                    text: layoutRow.active ? "●" : ""
                                    color: Colors.accent
                                    font.pixelSize: Config.type.sm
                                }
                            }

                            HoverHandler { id: rowHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // hyprctl eval
                                    applyProc.command = ["hyprctl", "eval",
                                        "SetLayout('" + layoutRow.modelData.label + "')"]
                                    applyProc.startDetached()
                                    layoutMenu.closeRequested()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
