import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

PanelWindow {
    id: powerMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    visible: open || closing
    onOpenChanged: {
        closing = !open
        if (open) {
            pendingAction = null
            selectedIndex = 0
            escCatcher.forceActiveFocus()
        }
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var actions: [
        { id: "logout",   icon: "󰍃", tint: true },
        { id: "lock",     icon: "󰌾" },
        { id: "suspend",  icon: "󰤄" },
        { id: "restart",  icon: "󰜉" },
        { id: "shutdown", icon: "⏻" }
    ]
    readonly property var destructiveIds: ["logout", "shutdown", "restart"]

    // Non-destructive actions run immediately; destructive ones set this and
    // the panel content swaps to the confirm view (same chrome, no 2nd slide).
    property var pendingAction: null

    property int selectedIndex: 0   // index into `actions`, active when pendingAction is null
    property int confirmChoice: 0   // 0 = Yes, 1 = No, active when pendingAction is set

    function requestAction(a) {
        if (destructiveIds.includes(a.id)) {
            pendingAction = a
            confirmChoice = 0
        } else {
            runAction(a.id)
        }
    }

    function runAction(id) {
        switch (id) {
            case "shutdown": actionProc.command = ["systemctl", "poweroff"]; break
            case "restart":  actionProc.command = ["systemctl", "reboot"]; break
            case "logout":   actionProc.command = ["hyprctl", "dispatch", "exit"]; break
            case "lock":     actionProc.command = ["hyprlock"]; break
            case "suspend":  actionProc.command = ["bash", "-c", "mpc -q pause; wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; systemctl suspend"]; break
        }
        actionProc.startDetached()
        pendingAction = null
        powerMenu.closeRequested()
    }

    Process { id: actionProc; command: ["echo"] }

    MouseArea {
        anchors.fill: parent
        onClicked: powerMenu.closeRequested()
    }

    Item {
        id: panel
        width: Config.powerMenu.width
        height: powerMenu.pendingAction
            ? Config.powerMenu.confirmHeight
            : Config.powerMenu.buttonSize * powerMenu.actions.length
                + Config.powerMenu.gap * (powerMenu.actions.length - 1)
                + Config.powerMenu.padding * 2
        Behavior on height { NumberAnimation { duration: Config.anim.popup; easing.type: Easing.OutCubic } }

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: powerMenu.open ? 0 : -width
        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !powerMenu.open) powerMenu.closing = false
            }
        }

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: Config.radius.hero
            bottomLeftRadius: Config.radius.hero
            topRightRadius: 0
            bottomRightRadius: 0
            color: Colors.surface
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Config.powerMenu.padding
                spacing: Config.powerMenu.gap
                visible: !powerMenu.pendingAction

                Repeater {
                    model: powerMenu.actions
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        required property int index
                        Layout.preferredWidth: Config.powerMenu.buttonSize
                        Layout.preferredHeight: Config.powerMenu.buttonSize
                        Layout.alignment: Qt.AlignHCenter
                        radius: Config.radius.xl
                        color: btn.modelData.tint
                            ? Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.15)
                            : (hover.hovered ? Colors.card : "transparent")
                        border.width: btn.index === powerMenu.selectedIndex ? 3 : 0
                        border.color: Colors.accent

                        Text {
                            anchors.centerIn: parent
                            text: btn.modelData.icon
                            color: btn.modelData.tint ? Colors.error : Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.display
                        }

                        HoverHandler {
                            id: hover
                            onHoveredChanged: if (hovered) powerMenu.selectedIndex = btn.index
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerMenu.requestAction(btn.modelData)
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Config.gap.lg
                spacing: Config.gap.md
                visible: !!powerMenu.pendingAction

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Are you sure?"
                    color: Colors.textStrong
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.md
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Config.gap.sm

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: Config.radius.lg
                        color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.2)
                        border.width: powerMenu.confirmChoice === 0 ? 3 : 0
                        border.color: Colors.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Yes"
                            color: Colors.error
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                            font.bold: true
                        }

                        HoverHandler { onHoveredChanged: if (hovered) powerMenu.confirmChoice = 0 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerMenu.runAction(powerMenu.pendingAction.id)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: Config.radius.lg
                        color: Colors.card
                        border.width: powerMenu.confirmChoice === 1 ? 3 : 0
                        border.color: Colors.accent

                        Text {
                            anchors.centerIn: parent
                            text: "No"
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                        }

                        HoverHandler { onHoveredChanged: if (hovered) powerMenu.confirmChoice = 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerMenu.pendingAction = null
                        }
                    }
                }
            }
        }
    }

    Item {
        id: escCatcher
        anchors.fill: parent
        focus: powerMenu.open
        Keys.onEscapePressed: powerMenu.pendingAction ? (powerMenu.pendingAction = null) : powerMenu.closeRequested()
        Keys.onUpPressed: if (!powerMenu.pendingAction)
            powerMenu.selectedIndex = (powerMenu.selectedIndex - 1 + powerMenu.actions.length) % powerMenu.actions.length
        Keys.onDownPressed: if (!powerMenu.pendingAction)
            powerMenu.selectedIndex = (powerMenu.selectedIndex + 1) % powerMenu.actions.length
        Keys.onLeftPressed: if (powerMenu.pendingAction) powerMenu.confirmChoice = 0
        Keys.onRightPressed: if (powerMenu.pendingAction) powerMenu.confirmChoice = 1
        Keys.onReturnPressed: {
            if (powerMenu.pendingAction) {
                if (powerMenu.confirmChoice === 0) powerMenu.runAction(powerMenu.pendingAction.id)
                else powerMenu.pendingAction = null
            } else {
                powerMenu.requestAction(powerMenu.actions[powerMenu.selectedIndex])
            }
        }
    }
}
