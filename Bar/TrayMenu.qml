import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../"
import "../config.js" as Config

PanelWindow {
    id: trayMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    property string itemId: ""
    property real targetY: 0
    visible: open || closing
    onOpenChanged: closing = !open

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    // Ignore (not Normal): with Normal this full-screen surface gets inset by
    // FrameReserve's exclusive zones, shifting our coordinate origin off the
    // output's corner — the panel would land frame.thick too far right and the
    // icon-y handed over from Bar (whose window ignores zones, so it spans the
    // real output) would be misaligned by the top frame strip as well.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Tray icons live in the (separate-window) left sidebar, so the item
    // clicked is handed over as a stable id via IPC rather than a direct
    // object reference — looked back up here against the same global
    // SystemTray.items model Bar/Tray.qml renders from.
    readonly property var activeItem: {
        for (const it of SystemTray.items.values)
            if (it.id === trayMenu.itemId) return it
        return null
    }

    QsMenuOpener {
        id: opener
        menu: trayMenu.activeItem ? trayMenu.activeItem.menu : null
    }

    // Menu entries arrive asynchronously (DBus layout fetch kicked off when
    // `menu` binds above), so an open request usually lands before the data.
    // The slide-in is gated on this: sliding out immediately would show a
    // near-empty panel that then grows and re-centers itself against the icon
    // a beat later — a visible drift into place.
    readonly property bool ready: opener.children.values.length > 0

    MouseArea {
        anchors.fill: parent
        onClicked: trayMenu.closeRequested()
    }

    Item {
        id: panel
        width: Config.trayMenu.width
        // Height and vertical position snap instantly (no Behaviors): they
        // must both be settled before the slide-in starts, and animating them
        // was exactly what made the panel drift after spawning.
        height: column.implicitHeight + Config.trayMenu.padding * 2

        anchors.left: parent.left
        anchors.top: parent.top
        // Center on the clicked tray icon's y, clamped so the panel — plus
        // its corner fillets — never runs off the top/bottom of the frame.
        anchors.topMargin: Math.max(
            Config.frame.thin + Config.radius.fillet,
            Math.min(trayMenu.targetY - height / 2, parent.height - height - Config.frame.thin - Config.radius.fillet)
        )
        // Open: docked flush against the sidebar's inner edge (the left frame
        // strip the tray lives in); closed: fully off-screen left.
        anchors.leftMargin: trayMenu.open && trayMenu.ready ? Config.frame.thick : -width
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !trayMenu.open) trayMenu.closing = false
            }
        }

        MouseArea { anchors.fill: parent }

        // Concave fillets melting the panel's left corners into the sidebar's
        // inner edge (which the panel docks flush against).
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
                anchors.margins: Config.trayMenu.padding
                spacing: Config.trayMenu.gap

                Repeater {
                    model: opener.children

                    delegate: Item {
                        id: entryItem
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: entryItem.modelData.isSeparator
                            ? (Config.gap.xs * 2 + 1)
                            : Config.trayMenu.rowHeight

                        Rectangle {
                            visible: entryItem.modelData.isSeparator
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: Colors.border
                        }

                        Rectangle {
                            visible: !entryItem.modelData.isSeparator
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: rowHover.hovered && entryItem.modelData.enabled ? Colors.card : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm

                                IconImage {
                                    visible: !!entryItem.modelData.icon
                                    Layout.preferredWidth: Config.type.md
                                    Layout.preferredHeight: Config.type.md
                                    source: entryItem.modelData.icon ? Quickshell.iconPath(entryItem.modelData.icon, true) : ""
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: entryItem.modelData.text
                                    color: entryItem.modelData.enabled ? Colors.text : Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: entryItem.modelData.buttonType !== QsMenuButtonType.None
                                        && entryItem.modelData.checkState === Qt.Checked
                                    text: entryItem.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓"
                                    color: Colors.accent
                                    font.pixelSize: Config.type.sm
                                }

                                Text {
                                    visible: entryItem.modelData.hasChildren
                                    text: "›"
                                    color: Colors.subtext
                                    font.pixelSize: Config.type.sm
                                }
                            }

                            HoverHandler {
                                id: rowHover
                                enabled: entryItem.modelData.enabled
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: entryItem.modelData.enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    entryItem.modelData.triggered()
                                    trayMenu.closeRequested()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
