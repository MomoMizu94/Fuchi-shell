import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import "../"
import "../config.js" as Config

// Network panel opened from NetworkIndicator: Wi-Fi toggle, current
// connection details, live up/down speed, and the scan/connect/forget flow
// for nearby Wi-Fi networks
PanelWindow {
    id: netMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    property real targetY: 0
    visible: open || closing
    onOpenChanged: {
        closing = !open
        if (open) {
            errorText = ""
            pskTarget = null
            probeProc.running = true
        } else {
            // Don't leave the radio scanning after the menu goes away
            if (wifiDev) wifiDev.scannerEnabled = false
        }
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

    readonly property var activeWifiNetwork: {
        if (!wifiDev) return null
        for (const n of wifiDev.networks.values)
            if (n.connected) return n
        return null
    }

    property string errorText: ""
    property var pskTarget: null   // WifiNetwork awaiting a password

    // Frequency + IPv4, fetched when the menu
    // opens and when the active connection changes
    property string freq: ""
    property string ipAddr: ""
    Process {
        id: probeProc
        command: ["bash", "-c",
            "freq=$(nmcli -t -f ACTIVE,FREQ dev wifi list 2>/dev/null | awk -F: '$1==\"yes\"{print $2\" \"$3; exit}'); " +
            "ip=$(ip -4 -o addr show up scope global 2>/dev/null | awk '{print $4; exit}'); " +
            "printf '{\"freq\":\"%s\",\"ip\":\"%s\"}\\n' \"$freq\" \"$ip\""]
        stdout: StdioCollector { id: probeOut }
        onExited: {
            try {
                const j = JSON.parse(probeOut.text)
                netMenu.freq = j.freq
                netMenu.ipAddr = j.ip
            } catch (e) {}
        }
    }
    onWiredUpChanged: if (open) probeProc.running = true
    onActiveWifiNetworkChanged: if (open) probeProc.running = true

    // Live up/down speeds — polled only while the menu is open
    property real up: 0
    property real down: 0
    Process {
        id: speedProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/netspeed.sh"]
        stdout: StdioCollector { id: speedOut }
        onExited: {
            try {
                const j = JSON.parse(speedOut.text)
                netMenu.up = j.up
                netMenu.down = j.down
            } catch (e) {}
        }
    }
    Timer {
        interval: Config.timer.netRefresh
        running: netMenu.open
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!speedProc.running) speedProc.running = true
    }

    function signalGlyph(strength) {
        if (strength > 0.75) return "󰤨"
        if (strength > 0.5) return "󰤥"
        if (strength > 0.25) return "󰤢"
        return "󰤟"
    }

    function connectivityLabel() {
        switch (Networking.connectivity) {
            case NetworkConnectivity.Portal: return "Captive portal"
            case NetworkConnectivity.Limited: return "No internet"
            case NetworkConnectivity.None: return "No connectivity"
            default: return ""
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: netMenu.closeRequested()
    }

    Item {
        id: panel
        width: Config.networkMenu.width
        // Height and vertical position snap instantly: they
        // must both be settled before the slide-in starts
        height: column.implicitHeight + Config.networkMenu.padding * 2

        anchors.left: parent.left
        anchors.top: parent.top
        // Center on the indicator's y, clamped so the panel — plus its corner
        // fillets — never runs off the top/bottom of the frame
        anchors.topMargin: Math.max(
            Config.frame.thin + Config.radius.fillet,
            Math.min(netMenu.targetY - height / 2, parent.height - height - Config.frame.thin - Config.radius.fillet)
        )
        // Open: docked flush against the sidebar's inner edge; closed: fully
        // off-screen left
        anchors.leftMargin: netMenu.open ? Config.frame.thick : -width
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !netMenu.open) netMenu.closing = false
            }
        }

        MouseArea { anchors.fill: parent }

        // Concave fillets melting the panel's left corners into the sidebar
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
                anchors.margins: Config.networkMenu.padding
                spacing: Config.networkMenu.gap

                // -- Header: title + wifi toggle --
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Config.networkMenu.rowHeight

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Config.gap.sm
                        anchors.rightMargin: Config.gap.sm
                        spacing: Config.gap.sm

                        Text {
                            text: netMenu.wiredUp ? "󰈀" : "󰤨"
                            color: netMenu.wiredUp || netMenu.wifiUp ? Colors.accent : Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.md
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Network"
                            color: Colors.textStrong
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            font.bold: true
                        }

                        Text {
                            text: "Wi-Fi"
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.micro
                        }

                        Rectangle {
                            id: wifiToggle
                            readonly property bool on: Networking.wifiEnabled
                            implicitWidth: 40
                            implicitHeight: 20
                            radius: height / 2
                            color: wifiToggle.on ? Colors.accent : Colors.inset

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 7
                                anchors.verticalCenter: parent.verticalCenter
                                x: wifiToggle.on ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                color: wifiToggle.on ? Colors.onAccent : Colors.subtext
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
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

                // -- Current connection --
                ColumnLayout {
                    visible: netMenu.wiredUp || netMenu.wifiUp
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    Layout.rightMargin: Config.gap.sm
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: netMenu.wiredUp
                            ? (netMenu.wiredDev && netMenu.wiredDev.network ? netMenu.wiredDev.network.name : "Wired")
                            : (netMenu.activeWifiNetwork ? netMenu.activeWifiNetwork.name : "")
                        color: Colors.text
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.sm
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const bits = []
                            if (netMenu.wiredUp && netMenu.wiredDev.linkSpeed > 0)
                                bits.push(netMenu.wiredDev.linkSpeed + " Mb/s link")
                            if (!netMenu.wiredUp && netMenu.freq !== "")
                                bits.push(netMenu.freq)
                            if (!netMenu.wiredUp && netMenu.activeWifiNetwork)
                                bits.push(Math.round(netMenu.activeWifiNetwork.signalStrength * 100) + "%")
                            if (netMenu.ipAddr !== "")
                                bits.push(netMenu.ipAddr)
                            return bits.join("  ·  ")
                        }
                        visible: text !== ""
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.micro
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: netMenu.connectivityLabel()
                        visible: text !== ""
                        color: Colors.warn
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.micro
                    }
                }

                // -- Live speeds --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    Layout.rightMargin: Config.gap.sm
                    spacing: Config.gap.lg

                    Text {
                        text: "󰅧 " + netMenu.up.toFixed(1) + " MB/s"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.micro
                    }
                    Text {
                        text: "󰅢 " + netMenu.down.toFixed(1) + " MB/s"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.micro
                    }
                    Item { Layout.fillWidth: true }
                }

                // -- Wired device (LAN half of LAN↔WLAN switching) --
                Item {
                    visible: netMenu.wiredDev !== null
                    Layout.fillWidth: true
                    implicitHeight: Config.networkMenu.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Config.radius.md
                        color: wiredHover.hovered ? Colors.card : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Config.gap.sm
                            anchors.rightMargin: Config.gap.sm
                            spacing: Config.gap.sm

                            Text {
                                text: "󰈀"
                                color: netMenu.wiredUp ? Colors.accent : Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.md
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Wired connection"
                                color: netMenu.wiredUp ? Colors.accent : Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.sm
                            }

                            Text {
                                text: netMenu.wiredUp ? "connected"
                                    : (netMenu.wiredDev && netMenu.wiredDev.hasLink ? "" : "no cable")
                                color: Colors.subtext
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.micro
                            }
                        }

                        HoverHandler { id: wiredHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!netMenu.wiredDev) return
                                if (netMenu.wiredUp) netMenu.wiredDev.disconnect()
                                else if (netMenu.wiredDev.network) netMenu.wiredDev.network.connect()
                            }
                        }
                    }
                }

                // -- Wi-Fi scan toggle --
                Item {
                    visible: netMenu.wifiDev !== null && Networking.wifiEnabled
                    Layout.fillWidth: true
                    implicitHeight: Config.networkMenu.rowHeight

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
                                text: netMenu.wifiDev && netMenu.wifiDev.scannerEnabled ? "󰀘" : "󰐕"
                                color: netMenu.wifiDev && netMenu.wifiDev.scannerEnabled ? Colors.accent : Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.md
                            }

                            Text {
                                Layout.fillWidth: true
                                text: netMenu.wifiDev && netMenu.wifiDev.scannerEnabled ? "Scanning…" : "Search for networks"
                                color: Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.sm
                            }
                        }

                        HoverHandler { id: scanHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (netMenu.wifiDev) netMenu.wifiDev.scannerEnabled = !netMenu.wifiDev.scannerEnabled
                        }
                    }
                }

                // -- Wi-Fi networks --
                Repeater {
                    model: netMenu.wifiDev && Networking.wifiEnabled
                        ? [...netMenu.wifiDev.networks.values].sort((a, b) => b.signalStrength - a.signalStrength)
                        : []

                    delegate: Item {
                        id: netRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Config.networkMenu.rowHeight

                        Connections {
                            target: netRow.modelData
                            function onConnectionFailed(reason) {
                                netMenu.errorText = "Failed to connect to " + netRow.modelData.name
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: rowHover.hovered ? Colors.card : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm

                                Text {
                                    text: netMenu.signalGlyph(netRow.modelData.signalStrength)
                                    color: netRow.modelData.connected ? Colors.accent : Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.md
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: netRow.modelData.name
                                    color: netRow.modelData.connected ? Colors.accent : Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: netRow.modelData.stateChanging
                                    text: "…"
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                }

                                Text {
                                    visible: netRow.modelData.security !== WifiSecurityType.Open
                                    text: "󰌾"
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                }

                                // Forget network, revealed on hover for known networks
                                Text {
                                    visible: rowHover.hovered && netRow.modelData.known
                                    text: "󰅖"
                                    color: forgetHover.hovered ? Colors.error : Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm

                                    HoverHandler { id: forgetHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Config.gap.xs
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: netRow.modelData.forget()
                                    }
                                }
                            }

                            HoverHandler { id: rowHover }
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                enabled: !netRow.modelData.stateChanging
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    netMenu.errorText = ""
                                    const n = netRow.modelData
                                    if (n.connected) n.disconnect()
                                    else if (n.known
                                        || n.security === WifiSecurityType.Open
                                        || n.security === WifiSecurityType.Owe) n.connect()
                                    else {
                                        netMenu.pskTarget = n
                                        pskInput.text = ""
                                        pskInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                // -- Password prompt for a secured, unknown network --
                ColumnLayout {
                    visible: netMenu.pskTarget !== null
                    Layout.fillWidth: true
                    Layout.topMargin: Config.gap.xs
                    spacing: Config.gap.xs

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: Config.gap.sm
                        text: netMenu.pskTarget ? "Password for " + netMenu.pskTarget.name : ""
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.micro
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Config.networkMenu.rowHeight
                        radius: Config.radius.md
                        color: Colors.inset

                        TextInput {
                            id: pskInput
                            anchors.fill: parent
                            anchors.leftMargin: Config.gap.sm
                            anchors.rightMargin: Config.gap.sm
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            clip: true

                            Keys.onReturnPressed: {
                                if (netMenu.pskTarget && text !== "") {
                                    netMenu.pskTarget.connectWithPsk(text)
                                    netMenu.pskTarget = null
                                    text = ""
                                }
                            }
                            Keys.onEscapePressed: {
                                netMenu.pskTarget = null
                                text = ""
                            }
                        }
                    }
                }

                Text {
                    visible: netMenu.errorText !== ""
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    text: netMenu.errorText
                    color: Colors.error
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.micro
                    elide: Text.ElideRight
                }
            }
        }
    }
}
