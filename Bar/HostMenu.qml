pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../"
import "../config.js" as Config
import "../secrets.js" as Secrets

PanelWindow {
    id: hostMenu
    signal closeRequested()

    readonly property var hosts: Secrets.hosts || []
    property bool open: false
    property bool closing: false
    property real targetY: 0
    property int selectedIndex: 0
    property string errorText: ""
    property string pendingHostId: ""
    visible: open || closing
    onOpenChanged: {
        closing = !open
        if (open) {
            selectedIndex = 0
            errorText = ""
            panel.forceActiveFocus()
        }
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Release the menu's keyboard focus immediately when launching/focusing a host.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function existingTerminal(host) {
        const appId = "fuchi-ssh-" + host.id
        for (const top of Hyprland.toplevels.values) {
            const id = top.wayland ? top.wayland.appId
                : (top.lastIpcObject ? top.lastIpcObject.class : "")
            if (id === appId)
                return top
        }
        return null
    }

    function chooseHost(host) {
        errorText = ""
        if (host.type === "web") {
            if (Qt.openUrlExternally(host.url))
                closeRequested()
            else
                errorText = "Could not open the browser. Check your default browser."
            return
        }
        if (host.type !== "ssh") {
            errorText = "Unknown host type. Use ssh or web in secrets.js."
            return
        }

        const existing = existingTerminal(host)
        if (existing && existing.lastIpcObject && existing.lastIpcObject.address) {
            closeRequested()
            Hyprland.dispatch("hl.dsp.focus({window=\"address:"
                + existing.lastIpcObject.address + "\"})")
            return
        }
        if (launchProc.running || pendingHostId === host.id)
            return

        pendingHostId = host.id
        // Fit smaller outputs while keeping Kitty's configured font size.
        const width = Math.max(1, Math.min(Config.hostMenu.terminalWidth,
            hostMenu.width - Config.frame.thick - Config.gap.xxl * 2))
        const height = Math.max(1, Math.min(Config.hostMenu.terminalHeight,
            hostMenu.height - Config.frame.thin * 2 - Config.gap.xxl * 2))
        const command = ["bash", Quickshell.shellDir + "/scripts/ssh-host.sh",
            host.id, host.name, host.destination,
            String(Math.round(width)), String(Math.round(height)),
            String(Config.frame.thick + Config.gap.md),
            String(Config.frame.thin + Config.gap.md)]
        if (host.startupCommand)
            command.push(host.startupCommand)
        launchProc.command = command
        launchProc.running = true
    }

    function moveSelection(delta) {
        const count = hostMenu.hosts.length
        if (count)
            selectedIndex = (selectedIndex + delta + count) % count
    }

    // Prevent another launch while Kitty's Wayland window is being mapped.
    Timer {
        id: launchCooldown
        interval: 2000
        onTriggered: hostMenu.pendingHostId = ""
    }

    Process {
        id: launchProc
        stderr: StdioCollector { id: launchError }
        stdout: StdioCollector { id: launchOutput }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                launchCooldown.restart()
                hostMenu.closeRequested()
            } else {
                hostMenu.pendingHostId = ""
                hostMenu.errorText = "Could not open the terminal. "
                    + (launchError.text.trim() || launchOutput.text.trim() || "Check Kitty and Hyprland.")
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: hostMenu.closeRequested()
    }

    Item {
        id: panel
        width: Math.min(Config.hostMenu.width, parent.width - Config.frame.thick - Config.frame.thin)
        height: column.implicitHeight + Config.hostMenu.padding * 2
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Math.max(Config.frame.thin + Config.radius.fillet,
            Math.min(hostMenu.targetY - height / 2,
                parent.height - height - Config.frame.thin - Config.radius.fillet))
        anchors.leftMargin: hostMenu.open ? Config.frame.thick : -width
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !hostMenu.open) hostMenu.closing = false
            }
        }

        Keys.onEscapePressed: hostMenu.closeRequested()
        Keys.onUpPressed: hostMenu.moveSelection(-1)
        Keys.onDownPressed: hostMenu.moveSelection(1)
        Keys.onTabPressed: hostMenu.moveSelection(1)
        Keys.onBacktabPressed: hostMenu.moveSelection(-1)
        Keys.onReturnPressed: {
            if (hostMenu.hosts.length) hostMenu.chooseHost(hostMenu.hosts[hostMenu.selectedIndex])
        }
        Keys.onEnterPressed: {
            if (hostMenu.hosts.length) hostMenu.chooseHost(hostMenu.hosts[hostMenu.selectedIndex])
        }

        MouseArea { anchors.fill: parent }

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
                anchors.margins: Config.hostMenu.padding
                spacing: Config.hostMenu.gap

                Repeater {
                    model: hostMenu.hosts
                    delegate: Rectangle {
                        id: hostRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: Config.hostMenu.rowHeight
                        radius: Config.radius.md
                        color: hostMenu.selectedIndex === index ? Colors.card : "transparent"
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name + ", " + (modelData.type === "ssh" ? "SSH" : "Web dashboard")

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Config.gap.sm
                            spacing: Config.gap.md

                            Text {
                                text: hostRow.modelData.type === "ssh" ? "󰆍" : "󰖟"
                                color: Colors.accent
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.sidebar.iconSize
                                Accessible.ignored: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: hostRow.modelData.name
                                    color: Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: hostRow.modelData.type === "ssh"
                                        ? hostRow.modelData.destination : hostRow.modelData.url
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.micro
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                text: hostMenu.pendingHostId === hostRow.modelData.id ? "Opening"
                                    : hostRow.modelData.type === "ssh" ? "SSH" : "Web"
                                color: Colors.subtext
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.label
                            }
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) hostMenu.selectedIndex = hostRow.index
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: hostMenu.chooseHost(hostRow.modelData)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: hostMenu.hosts.length === 0
                    text: "Add a host in secrets.js."
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }
                Text {
                    Layout.fillWidth: true
                    visible: hostMenu.errorText !== ""
                    text: hostMenu.errorText
                    color: Colors.error
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.label
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
