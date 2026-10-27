pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import "../"
import "../config.js" as Config

PanelWindow {
    id: menu
    required property var service
    signal closeRequested()
    property bool open: false
    property bool closing: false
    property real targetY: 0
    visible: open || closing
    onOpenChanged: {
        closing = !open && Settings.animationPopup > 0
        if (open) {
            list.positionViewAtBeginning()
            panel.forceActiveFocus()
        }
    }
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function sourceDetail(state) {
        let detail = service.checkedText(state.lastSuccess)
        if (state.error) {
            return (state.lastSuccess ? "Last known updates. " + detail + ". " : "Not checked yet. ") + state.error
        }
        if (state.checking) return "Checking… " + detail
        if (state.lastSuccess && state.packages.length === 0) return "Up to date. " + detail
        return detail
    }

    // One flat model keeps large update lists virtualized by ListView.
    readonly property var rows: {
        const result = []
        const sources = [
            { title: "Repositories", state: service.repositories },
            { title: "AUR", state: service.aur }
        ]
        for (const source of sources) {
            const state = source.state
            // Keep timestamps in delegate bindings so clock ticks do not replace
            // the model and reset a reader's scroll position.
            result.push({ section: true, title: source.title, state: state })
            for (const entry of state.packages) {
                result.push({ section: false, title: entry.name,
                    detail: entry.installed + " → " + entry.available })
            }
        }
        return result
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.closeRequested()
    }

    FocusScope {
        id: panel
        objectName: "updatesPanel"
        width: Math.max(1, Math.min(Config.updates.width,
            menu.width - Config.frame.thick - Config.frame.thin))
        height: Math.max(1, Math.min(Config.updates.maxHeight, content.implicitHeight + 2 * Config.gap.xl,
            menu.height - 2 * (Config.frame.thin + Config.radius.fillet)))
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Math.max(Config.frame.thin + Config.radius.fillet,
            Math.min(menu.targetY - height / 2,
                menu.height - height - Config.frame.thin - Config.radius.fillet))
        anchors.leftMargin: menu.open ? Config.frame.thick : -width
        Keys.onEscapePressed: menu.closeRequested()
        Keys.onDownPressed: list.contentY = Math.min(list.originY + Math.max(0, list.contentHeight - list.height), list.contentY + 48)
        Keys.onUpPressed: list.contentY = Math.max(list.originY, list.contentY - 48)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_PageDown) {
                list.contentY = Math.min(list.originY + Math.max(0, list.contentHeight - list.height), list.contentY + list.height)
            } else if (event.key === Qt.Key_PageUp) {
                list.contentY = Math.max(list.originY, list.contentY - list.height)
            } else {
                return
            }
            event.accepted = true
        }

        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Settings.animationPopup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !menu.open) menu.closing = false
            }
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

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: Config.gap.xl
                spacing: Config.gap.md

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Updates"
                        color: Colors.text
                        font.family: Settings.fontFamily
                        font.pixelSize: Config.type.lg
                    }
                    SettingsButton {
                        objectName: "checkUpdatesButton"
                        text: menu.service.busy ? "Checking…" : "Check now"
                        enabled: !menu.service.busy
                        onClicked: menu.service.refresh()
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: menu.service.summary
                    textFormat: Text.PlainText
                    color: menu.service.hasError ? Colors.error : Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Colors.border
                }
                ListView {
                    id: list
                    objectName: "updatePackages"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: contentHeight
                    clip: true
                    model: menu.rows
                    spacing: Config.gap.md
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        id: scrollBar
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 5
                            radius: 2
                            color: Colors.subtext
                            opacity: scrollBar.active ? 0.9 : 0.5
                        }
                    }
                    delegate: Column {
                        id: row
                        required property var modelData
                        width: list.width - Config.gap.md
                        spacing: Config.gap.xs
                        topPadding: modelData.section ? Config.gap.sm : 0
                        Text {
                            width: parent.width
                            text: row.modelData.title + (row.modelData.section && row.modelData.state.lastSuccess
                                ? " · " + row.modelData.state.packages.length : "")
                            textFormat: Text.PlainText
                            color: row.modelData.section ? Colors.accent : Colors.text
                            font.family: Settings.fontFamily
                            font.pixelSize: row.modelData.section ? Config.type.base : Config.type.sm
                            font.bold: row.modelData.section
                            wrapMode: Text.WrapAnywhere
                        }
                        Text {
                            width: parent.width
                            text: row.modelData.section ? menu.sourceDetail(row.modelData.state) : row.modelData.detail
                            textFormat: Text.PlainText
                            color: row.modelData.section && row.modelData.state.error ? Colors.error : Colors.subtext
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.micro
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Checks hourly. Refresh after updating packages."
                    color: Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.micro
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
