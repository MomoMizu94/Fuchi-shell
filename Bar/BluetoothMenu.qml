import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import Quickshell.Widgets
import "../"
import "../config.js" as Config

PanelWindow {
    id: btMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    property real targetY: 0
    visible: open || closing
    onOpenChanged: {
        closing = !open
        // Don't leave the radio scanning after the menu goes away.
        if (!open && adapter) adapter.discovering = false
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    // Ignore (not Normal): with Normal this full-screen surface gets inset by
    // FrameReserve's exclusive zones, shifting our coordinate origin off the
    // output's corner — the panel would land frame.thick too far right and the
    // icon-y handed over from Bar (whose window ignores zones, so it spans the
    // real output) would be misaligned by the top frame strip as well.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool ready: adapter !== null

    MouseArea {
        anchors.fill: parent
        onClicked: btMenu.closeRequested()
    }

    Item {
        id: panel
        width: Config.bluetoothMenu.width
        // Height and vertical position snap instantly (no Behaviors): they
        // must both be settled before the slide-in starts — animating them
        // makes the panel drift after spawning (see TrayMenu).
        height: column.implicitHeight + Config.bluetoothMenu.padding * 2

        anchors.left: parent.left
        anchors.top: parent.top
        // Center on the bar icon's y, clamped so the panel — plus its corner
        // fillets — never runs off the top/bottom of the frame.
        anchors.topMargin: Math.max(
            Config.frame.thin + Config.radius.fillet,
            Math.min(btMenu.targetY - height / 2, parent.height - height - Config.frame.thin - Config.radius.fillet)
        )
        // Open: docked flush against the sidebar's inner edge (the left frame
        // strip the indicator lives in); closed: fully off-screen left.
        anchors.leftMargin: btMenu.open && btMenu.ready ? Config.frame.thick : -width
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !btMenu.open) btMenu.closing = false
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
                anchors.margins: Config.bluetoothMenu.padding
                spacing: Config.bluetoothMenu.gap

                // ── Header: title + power toggle ──
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Config.bluetoothMenu.rowHeight

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Config.gap.sm
                        anchors.rightMargin: Config.gap.sm
                        spacing: Config.gap.sm

                        Text {
                            text: "󰂯"
                            color: btMenu.adapter && btMenu.adapter.enabled ? Colors.accent : Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.md
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Bluetooth"
                            color: Colors.textStrong
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            font.bold: true
                        }

                        // Pill toggle for adapter power
                        Rectangle {
                            id: powerToggle
                            readonly property bool on: btMenu.adapter && btMenu.adapter.enabled
                            implicitWidth: 40
                            implicitHeight: 20
                            radius: height / 2
                            color: powerToggle.on
                                ? Colors.accent
                                : Colors.inset

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                anchors.verticalCenter: parent.verticalCenter
                                x: powerToggle.on ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                color: powerToggle.on ? Colors.onAccent : Colors.subtext
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (btMenu.adapter) btMenu.adapter.enabled = !btMenu.adapter.enabled
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Config.gap.xs * 2 + 1
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Colors.border
                    }
                }

                // ── Bluetooth off hint ──
                Item {
                    visible: !(btMenu.adapter && btMenu.adapter.enabled)
                    Layout.fillWidth: true
                    implicitHeight: Config.bluetoothMenu.rowHeight

                    Text {
                        anchors.centerIn: parent
                        text: "Bluetooth is off"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.sm
                    }
                }

                // ── Paired devices ──
                Repeater {
                    model: Bluetooth.devices

                    // Per-delegate visibility (not a values.filter binding):
                    // the filter wouldn't re-run when one device's `paired`
                    // flips, since only insert/remove notifies valuesChanged.
                    delegate: Item {
                        id: pairedRow
                        required property var modelData
                        readonly property bool busy: pairedRow.modelData.state === BluetoothDeviceState.Connecting
                            || pairedRow.modelData.state === BluetoothDeviceState.Disconnecting
                        visible: btMenu.adapter && btMenu.adapter.enabled && pairedRow.modelData.paired
                        Layout.fillWidth: true
                        implicitHeight: visible ? Config.bluetoothMenu.rowHeight : 0

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: rowHover.hovered ? Colors.card : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm

                                IconImage {
                                    Layout.preferredWidth: Config.type.md
                                    Layout.preferredHeight: Config.type.md
                                    source: pairedRow.modelData.icon ? Quickshell.iconPath(pairedRow.modelData.icon, true) : ""
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: pairedRow.modelData.name
                                    color: pairedRow.modelData.connected ? Colors.accent : Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: pairedRow.busy
                                    text: "…"
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                }

                                Text {
                                    visible: !pairedRow.busy && pairedRow.modelData.batteryAvailable
                                    text: Math.round(pairedRow.modelData.battery * 100) + "%"
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                }

                                // Forget button, revealed on row hover
                                Text {
                                    visible: rowHover.hovered
                                    text: "󰅖"
                                    color: forgetHover.hovered ? Colors.error : Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm

                                    HoverHandler { id: forgetHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Config.gap.xs
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pairedRow.modelData.forget()
                                    }
                                }
                            }

                            HoverHandler { id: rowHover }
                            MouseArea {
                                anchors.fill: parent
                                // Leave the forget button's own MouseArea on top
                                z: -1
                                enabled: !pairedRow.busy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pairedRow.modelData.connected
                                    ? pairedRow.modelData.disconnect()
                                    : pairedRow.modelData.connect()
                            }
                        }
                    }
                }

                // ── Pair new device (scan toggle) ──
                Item {
                    visible: btMenu.adapter && btMenu.adapter.enabled
                    Layout.fillWidth: true
                    implicitHeight: Config.bluetoothMenu.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Config.radius.md
                        color: scanHover.hovered ? Colors.card : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Config.gap.sm
                            anchors.rightMargin: Config.gap.sm
                            spacing: Config.gap.sm

                            Text {
                                text: btMenu.adapter && btMenu.adapter.discovering ? "󰀘" : "󰐕"
                                color: btMenu.adapter && btMenu.adapter.discovering ? Colors.accent : Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.md
                            }

                            Text {
                                Layout.fillWidth: true
                                text: btMenu.adapter && btMenu.adapter.discovering ? "Scanning…" : "Pair new device"
                                color: Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.sm
                            }
                        }

                        HoverHandler { id: scanHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (btMenu.adapter) btMenu.adapter.discovering = !btMenu.adapter.discovering
                        }
                    }
                }

                // ── Discovered (unpaired) devices, while scanning ──
                Repeater {
                    model: Bluetooth.devices

                    delegate: Item {
                        id: foundRow
                        required property var modelData
                        visible: btMenu.adapter && btMenu.adapter.enabled && btMenu.adapter.discovering
                            && !foundRow.modelData.paired && foundRow.modelData.deviceName !== ""
                        Layout.fillWidth: true
                        implicitHeight: visible ? Config.bluetoothMenu.rowHeight : 0

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: foundHover.hovered ? Colors.card : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm

                                IconImage {
                                    Layout.preferredWidth: Config.type.md
                                    Layout.preferredHeight: Config.type.md
                                    source: foundRow.modelData.icon ? Quickshell.iconPath(foundRow.modelData.icon, true) : ""
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: foundRow.modelData.deviceName
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: foundRow.modelData.pairing
                                    text: "pairing…"
                                    color: Colors.accent
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                }
                            }

                            HoverHandler { id: foundHover }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !foundRow.modelData.pairing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // Trust up front so it auto-reconnects later.
                                    foundRow.modelData.trusted = true
                                    foundRow.modelData.pair()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
