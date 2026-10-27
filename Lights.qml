pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "config.js" as Config

FocusScope {
    id: root
    property bool active: false
    signal closeRequested()
    property alias controller: hue
    property int requestedBrightness: -1
    implicitHeight: content.implicitHeight + Config.gap.lg * 2
    clip: true
    Keys.onEscapePressed: root.closeRequested()

    function focusControls() {
        if (powerButton.visible) powerButton.forceActiveFocus()
        else if (reconnectButton.visible) reconnectButton.forceActiveFocus()
        else scanButton.forceActiveFocus()
    }

    HueService {
        id: hue
        active: root.active
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        contentHeight: content.implicitHeight + Config.gap.lg * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: content
            x: Config.gap.lg
            y: Config.gap.lg
            width: scroll.width - Config.gap.lg * 2
            spacing: Config.gap.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Config.gap.md
                Text {
                    text: "󰌵  Hue Go"
                    color: Colors.text
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.md
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: hue.busy ? "Working…" : hue.connected
                        ? (hue.state.power ? "On" : "Off") + (hue.state.model ? " · " + hue.state.model : "")
                        : hue.state.address ? "Disconnected" : "Choose a nearby lamp"
                    color: Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                    elide: Text.ElideRight
                }
                SettingsButton {
                    id: powerButton
                    objectName: "huePower"
                    visible: hue.connected
                    text: hue.state.power ? "Turn off" : "Turn on"
                    enabled: !hue.busy
                    onClicked: hue.send({op: "power", value: !hue.state.power})
                }
                SettingsButton {
                    id: reconnectButton
                    text: "Reconnect"
                    visible: !!hue.state.address && !hue.connected && hue.ready
                    enabled: !hue.busy
                    onClicked: hue.send({op: "refresh"})
                }
                SettingsButton {
                    objectName: "hueForget"
                    text: "Forget"
                    visible: !!hue.state.address
                    enabled: hue.ready && !hue.busy
                    onClicked: hue.send({op: "forget"})
                }
                SettingsButton {
                    id: scanButton
                    objectName: "hueScan"
                    text: hue.ready ? "Scan for lamps" : "Retry"
                    visible: !hue.connected
                    enabled: !hue.busy
                    onClicked: hue.ready ? hue.send({op: "scan"}) : hue.start()
                }
            }

            RowLayout {
                visible: hue.connected
                Layout.fillWidth: true
                spacing: Config.gap.md
                Text {
                    text: "Brightness"
                    color: Colors.text
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                }
                Slider {
                    id: brightness
                    objectName: "hueBrightness"
                    Layout.fillWidth: true
                    from: 1; to: 100; stepSize: 1
                    enabled: hue.connected && !hue.busy
                    onMoved: {
                        root.requestedBrightness = Math.round(value)
                        if (!pressed) brightnessCommit.restart()
                    }
                    onPressedChanged: if (!pressed && root.requestedBrightness >= 0) brightnessCommit.restart()
                    Binding {
                        target: brightness
                        property: "value"
                        when: !brightness.pressed && root.requestedBrightness < 0 && !hue.busy
                        value: hue.state.brightness === undefined ? 100 : hue.state.brightness
                        restoreMode: Binding.RestoreNone
                    }
                    background: Rectangle {
                        x: brightness.leftPadding
                        y: brightness.topPadding + brightness.availableHeight / 2 - height / 2
                        width: brightness.availableWidth; height: 6
                        radius: 3; color: Colors.inset
                        Rectangle { width: brightness.visualPosition * parent.width; height: parent.height; radius: 3; color: Colors.accent }
                    }
                    handle: Rectangle {
                        x: brightness.leftPadding + brightness.visualPosition * (brightness.availableWidth - width)
                        y: brightness.topPadding + brightness.availableHeight / 2 - height / 2
                        width: 18; height: 18; radius: 9
                        color: Colors.text
                        border.width: brightness.visualFocus ? 2 : 0
                        border.color: Colors.accent
                    }
                }
                Text {
                    Layout.preferredWidth: 52
                    text: Math.round(brightness.value) + "%"
                    color: Colors.text
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: hue.connected
                spacing: Config.gap.md
                SettingsButton {
                    text: "Warm white"
                    visible: !!hue.state.temperature
                    enabled: !hue.busy
                    onClicked: hue.send({op: "temperature", value: 2700})
                }
                Repeater {
                    model: hue.state.color ? ["#ff7055", "#ffc45c", "#75d99a", "#66baff", "#bc86ff"] : []
                    delegate: Button {
                        id: swatch
                        required property string modelData
                        implicitWidth: 32; implicitHeight: 32
                        enabled: !hue.busy
                        Accessible.name: "Set lamp color " + modelData
                        ToolTip.visible: hovered
                        ToolTip.text: modelData
                        background: Rectangle {
                            radius: width / 2
                            color: swatch.modelData
                            border.width: swatch.visualFocus ? 3 : 0
                            border.color: Colors.text
                        }
                        onClicked: hue.send({op: "color", value: modelData})
                    }
                }
                TextField {
                    id: colorInput
                    objectName: "hueColor"
                    visible: !!hue.state.color
                    width: 130
                    height: 40
                    placeholderText: "#RRGGBB"
                    maximumLength: 7
                    color: Colors.text
                    placeholderTextColor: Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                    validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                    background: Rectangle {
                        color: Colors.inset; radius: Config.radius.lg
                        border.width: 1
                        border.color: colorInput.activeFocus ? Colors.accent : Colors.border
                    }
                    onAccepted: if (acceptableInput && !hue.busy) hue.send({op: "color", value: text})
                }
                SettingsButton {
                    text: "Apply color"
                    visible: !!hue.state.color
                    enabled: colorInput.acceptableInput && !hue.busy
                    onClicked: hue.send({op: "color", value: colorInput.text})
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: !hue.connected && (hue.state.devices || []).length > 0
                spacing: Config.gap.sm
                Repeater {
                    model: hue.connected ? [] : (hue.state.devices || [])
                    delegate: SettingsButton {
                        required property var modelData
                        text: "Connect " + modelData.name + " (" + modelData.address + ")"
                        enabled: !hue.busy
                        onClicked: hue.send({op: "select", address: modelData.address})
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: hue.error !== ""
                text: hue.error
                wrapMode: Text.Wrap
                color: Colors.error
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.sm
            }
        }
    }
    Timer {
        id: brightnessCommit
        interval: 200
        onTriggered: {
            if (hue.connected && hue.busy) { restart(); return }
            if (hue.connected && root.requestedBrightness >= 0)
                hue.send({op: "brightness", value: root.requestedBrightness})
            root.requestedBrightness = -1
        }
    }
    Connections {
        target: hue
        function onConnectedChanged() {
            if (!hue.connected) {
                brightnessCommit.stop()
                root.requestedBrightness = -1
            }
        }
    }
}
