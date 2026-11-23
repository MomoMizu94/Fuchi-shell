import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../"
import "../config.js" as Config

// Floating context menu for a right-clicked tray icon (Bar/Tray.qml), sliding
// out from the sidebar next to the icon that was clicked
PanelWindow {
    id: trayMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    property string itemId: ""
    property real targetY: 0
    visible: open || closing
    onOpenChanged: closing = !open && dock.x > -dock.width

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    // Ignore (not Normal) keeps this window's coordinates lined up with Bar's:
    // both windows then span the full screen, so the icon y-position Bar
    // hands over lands in the right spot here too
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Bar/Tray.qml lives in a different window, so it can't hand this menu
    // the clicked item directly — just its id, over IPC. Look the actual
    // item back up here, in the same global list Bar/Tray.qml uses
    readonly property var activeItem: {
        for (const it of SystemTray.items.values)
            if (it.id === trayMenu.itemId) return it
        return null
    }

    MouseArea {
        anchors.fill: parent
        onClicked: trayMenu.closeRequested()
    }

    Loader {
        id: dock
        readonly property bool docked: true
        readonly property var menuHandle: trayMenu.visible && trayMenu.activeItem ? trayMenu.activeItem.menu : null
        readonly property real edge: Config.frame.thin + Config.radius.fillet
        width: Math.min(Config.trayMenu.width, Math.max(0, (parent.width - Config.frame.thick) / 2))
        x: trayMenu.open && item && item.hasRows ? Config.frame.thick : -width
        y: Math.max(edge, Math.min(trayMenu.targetY - height / 2, parent.height - edge - height))
        sourceComponent: menuPanel

        Behavior on x {
            NumberAnimation {
                duration: Settings.animationPopup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !trayMenu.open) trayMenu.closing = false
            }
        }

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
    }

    // Each open branch gets its own opener so the tray app can populate it on demand
    Component {
        id: menuPanel
        Rectangle {
            id: panel
            readonly property bool hasRows: entries.count > 0
            property Item branchRow: null
            readonly property var branch: branchRow ? branchRow.modelData : null
            readonly property bool canExpand: !!branch && branch.enabled && branch.hasChildren
            implicitHeight: Math.min(rows.implicitHeight + Config.trayMenu.padding * 2,
                trayMenu.height - (parent.docked ? dock.edge * 2 : Config.frame.thin * 2))
            topLeftRadius: parent.docked ? 0 : Config.radius.lg
            bottomLeftRadius: topLeftRadius
            topRightRadius: parent.docked ? Config.radius.hero : Config.radius.lg
            bottomRightRadius: topRightRadius
            color: Colors.surface

            QsMenuOpener {
                id: opener
                menu: panel.parent.menuHandle
                onMenuChanged: panel.branchRow = null
            }
            Connections {
                target: trayMenu
                function onOpenChanged() { panel.branchRow = null }
            }
            MouseArea { anchors.fill: parent }

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: Config.trayMenu.padding
                contentHeight: rows.implicitHeight
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: panel.branchRow = null
                ScrollWheel { view: viewport }

                Column {
                    id: rows
                    width: viewport.width
                    spacing: Config.trayMenu.gap
                    Repeater {
                        id: entries
                        model: opener.children
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool actionable: modelData.enabled && !modelData.isSeparator
                            width: rows.width
                            height: modelData.isSeparator ? Config.gap.xs * 2 + 1 : Config.trayMenu.rowHeight
                            radius: Config.radius.md
                            color: actionable && (pointer.containsMouse || panel.branchRow === row)
                                ? Colors.card : "transparent"

                            Rectangle {
                                visible: row.modelData.isSeparator
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 1
                                color: Colors.border
                            }
                            RowLayout {
                                visible: !row.modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm
                                IconImage {
                                    visible: !!row.modelData.icon
                                    Layout.preferredWidth: Config.type.md
                                    Layout.preferredHeight: Config.type.md
                                    source: row.modelData.icon || ""
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.text
                                    textFormat: Text.PlainText
                                    color: row.modelData.enabled ? Colors.text : Colors.subtext
                                    font.family: Settings.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: row.modelData.buttonType !== QsMenuButtonType.None
                                        && row.modelData.checkState === Qt.Checked
                                    text: row.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓"
                                    color: Colors.accent
                                    font.pixelSize: Config.type.sm
                                }
                                Text {
                                    visible: row.modelData.hasChildren
                                    text: "›"
                                    color: Colors.subtext
                                    font.pixelSize: Config.type.sm
                                }
                            }
                            MouseArea {
                                id: pointer
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onEntered: panel.branchRow = row.actionable && row.modelData.hasChildren ? row : null
                                onClicked: {
                                    if (!row.actionable) return
                                    if (row.modelData.hasChildren) {
                                        panel.branchRow = row
                                    } else {
                                        row.modelData.triggered()
                                        trayMenu.closeRequested()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Loader {
                // Put each submenu in the overlay so hover hit testing reaches its rows
                parent: trayMenu.contentItem
                z: panel.parent.z + 1
                readonly property bool docked: false
                readonly property var menuHandle: panel.branch
                active: trayMenu.open && panel.canExpand
                visible: active && item && item.hasRows
                width: dock.width
                x: panel.parent.x + panel.width + width <= trayMenu.width
                    ? panel.parent.x + panel.width : Math.max(0, panel.parent.x - width)
                y: {
                    const rowY = panel.branchRow ? panel.branchRow.y - viewport.contentY : 0
                    const top = panel.parent.y
                    return Math.max(Config.frame.thin,
                        Math.min(top + rowY, trayMenu.height - Config.frame.thin - height))
                }
                sourceComponent: menuPanel
            }
        }
    }
}
