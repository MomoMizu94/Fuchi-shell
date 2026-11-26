pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../"
import "../config.js" as Config

PanelWindow {
    id: menu
    property bool open: false
    property real targetY: height / 2
    property string helper: Quickshell.shellDir + "/scripts/clipboard-history.py"
    property var entries: []
    property string lastResult: ""
    property string error: ""
    property bool confirmingClear: false
    readonly property var matches: {
        const query = search.text.trim().toLowerCase()
        if (!query) return entries
        return entries.filter(entry => entry.label.toLowerCase().includes(query)
            || (entry.binary && "image".includes(query)))
    }

    visible: open
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        confirmingClear = false
        search.clear()
        error = ""
        if (open) {
            search.forceActiveFocus()
        } else {
            entries = []
            lastResult = ""
        }
    }

    function restore(index) {
        const entry = matches[index]
        if (!entry || copy.running || confirmingClear || wipe.running) return
        error = ""
        copy.command = ["python3", helper, entry.binary ? "copy-binary" : "copy-text", entry.key]
        copy.running = true
    }

    Timer {
        running: menu.open
        repeat: true
        triggeredOnStart: true
        interval: 3000
        onTriggered: if (!load.running && !menu.confirmingClear && !wipe.running) load.running = true
    }
    Process {
        id: load
        command: ["python3", menu.helper, "list"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: listError }
        onExited: (code) => {
            if (!menu.open) return
            if (code !== 0) {
                menu.error = listError.text.trim() || "Could not read clipboard history."
                menu.lastResult = ""
                menu.entries = []
            } else if (output.text !== menu.lastResult) {
                menu.lastResult = output.text
                list.replaceEntries(JSON.parse(output.text))
                menu.error = ""
            }
        }
    }
    Process {
        id: wipe
        command: ["env", "cliphist", "wipe"]
        onExited: (code) => {
            menu.confirmingClear = false
            if (!menu.open) return
            search.forceActiveFocus()
            if (code !== 0) {
                menu.error = "Could not clear clipboard history."
                return
            }
            menu.entries = []
            menu.lastResult = ""
            menu.error = ""
            search.clear()
            load.running = true
        }
    }
    Process {
        id: copy
        stderr: StdioCollector { id: copyError }
        onExited: (code) => {
            if (code === 0) menu.open = false
            else menu.error = copyError.text.trim() || "Could not restore this entry."
        }
    }

    MouseArea { anchors.fill: parent; onClicked: menu.open = false }
    Rectangle {
        id: panel
        x: Config.frame.thick
        width: Math.max(1, Math.min(460, menu.width - x - Config.frame.thin))
        height: Math.max(1, Math.min(menu.height - 2 * Config.frame.thin,
            layout.implicitHeight + 2 * Config.gap.lg))
        y: Math.max(Config.frame.thin, Math.min(menu.targetY - height / 2, menu.height - height - Config.frame.thin))
        color: Colors.surface
        topRightRadius: Config.radius.hero
        bottomRightRadius: Config.radius.hero
        clip: true

        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Config.gap.lg
            spacing: Config.gap.sm

            RowLayout {
                Layout.fillWidth: true
                Keys.onEscapePressed: {
                    if (menu.confirmingClear) {
                        menu.confirmingClear = false
                        search.forceActiveFocus()
                    } else menu.open = false
                }
                Text {
                    Layout.fillWidth: true
                    text: menu.confirmingClear ? "Clear all history?" : "Clipboard history"
                    wrapMode: Text.Wrap
                    color: Colors.text
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.lg
                }
                SettingsButton {
                    objectName: "confirmClearClipboard"
                    visible: menu.confirmingClear
                    enabled: !load.running && !wipe.running
                    text: "Clear all"
                    onClicked: wipe.running = true
                }
                SettingsButton {
                    objectName: "clearClipboard"
                    text: menu.confirmingClear ? "Cancel" : "Clear"
                    enabled: !copy.running && !wipe.running && (menu.confirmingClear || menu.entries.length > 0)
                    onClicked: {
                        menu.confirmingClear = !menu.confirmingClear
                        if (menu.confirmingClear) forceActiveFocus()
                        else search.forceActiveFocus()
                    }
                }
            }
            TextField {
                id: search
                enabled: !menu.confirmingClear && !wipe.running
                Layout.fillWidth: true
                placeholderText: "Search clipboard"
                Accessible.name: placeholderText
                color: Colors.text
                placeholderTextColor: Colors.subtext
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.sm
                padding: Config.gap.sm
                background: Rectangle {
                    color: Colors.inset
                    radius: Config.radius.md
                    border.color: search.activeFocus ? Colors.accent : Colors.border
                }
                onTextChanged: list.currentIndex = menu.matches.length ? 0 : -1
                Keys.onEscapePressed: menu.open = false
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onUpPressed: list.decrementCurrentIndex()
                onAccepted: menu.restore(list.currentIndex)
            }
            Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: menu.error || (menu.matches.length ? "" : menu.entries.length ? "No matches"
                    : load.running && !menu.lastResult ? "Loading…" : "No copied items yet")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: menu.error ? Colors.error : Colors.subtext
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.sm
            }
            ListView {
                id: list
                objectName: "clipboardEntries"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(420, contentHeight)
                visible: count > 0
                clip: true
                model: menu.matches
                boundsBehavior: Flickable.StopAtBounds

                function replaceEntries(entries) {
                    const selectedKey = menu.matches[currentIndex]?.key
                    const first = atYBeginning ? null : itemAt(1, contentY)
                    const firstKey = first?.modelData.key
                    const offset = first ? contentY - first.y : 0

                    menu.entries = entries
                    const selected = menu.matches.findIndex(entry => entry.key === selectedKey)
                    currentIndex = count ? Math.max(0, selected) : -1
                    forceLayout()
                    const index = menu.matches.findIndex(entry => entry.key === firstKey)
                    if (index < 0) {
                        positionViewAtBeginning()
                    } else {
                        positionViewAtIndex(index, ListView.Beginning)
                        const row = itemAtIndex(index)
                        if (row) contentY = row.y + offset
                        returnToBounds()
                    }
                }

                ScrollWheel { view: list }
                ScrollBar.vertical: ScrollBar {
                    policy: list.contentHeight > list.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }
                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var modelData
                    width: list.width
                    height: modelData.binary ? 80 : 44
                    radius: Config.radius.md
                    color: row.ListView.isCurrentItem ? Qt.alpha(Colors.accent, 0.20)
                        : pointer.containsMouse ? Colors.card : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.onPressAction: menu.restore(row.index)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Config.gap.sm
                        spacing: Config.gap.md
                        Image {
                            id: thumb
                            visible: row.modelData.binary
                            Layout.preferredWidth: 102
                            Layout.fillHeight: true
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignLeft
                            cache: false
                            Process {
                                command: ["python3", menu.helper, "thumbnail", row.modelData.key]
                                running: row.modelData.binary && menu.open
                                stdout: StdioCollector { onStreamFinished: thumb.source = text.trim() }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.sm
                            color: Colors.text
                        }
                    }
                    MouseArea {
                        id: pointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menu.restore(row.index)
                    }
                }
            }
        }
    }
}
