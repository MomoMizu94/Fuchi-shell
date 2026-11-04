import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "config.js" as Config
import "settings.js" as Paths

FloatingWindow {
    id: window
    title: "Fuchi-shell Oceanus"
    visible: false
    implicitWidth: 720
    implicitHeight: 540
    minimumSize: Qt.size(420, 360)
    color: Colors.surface

    property var helperCommand: ["python3", Quickshell.shellDir + "/scripts/oceanus.py"]
    property string statePath: Quickshell.statePath("oceanus.json")
    property var projects: []
    property string selectedProject: ""
    property string errorText: ""
    property bool openRequested: false
    readonly property bool busy: helper.running
    property string operation: ""

    function request(action) {
        if (busy) return
        errorText = ""
        operation = action
        let command = helperCommand.concat([action, "--state", statePath])
        if (action === "launch") {
            command = command.concat(["--project", selectedProject, "--python",
                Paths.absolutePath(Config.oceanus.python, Quickshell.env("HOME"))])
        }
        helper.command = command
        helper.running = true
    }

    function showOceanus(newConversation) {
        if (busy) return
        openRequested = true
        request(newConversation ? "projects" : "open")
    }

    function hidePicker() {
        openRequested = false
        visible = false
    }

    function presentPicker() {
        if (!openRequested) return
        if (!Quickshell.env("WAYLAND_DISPLAY")) activatePicker()
        else if (!placement.running) placement.running = true
    }

    function activatePicker() {
        if (!openRequested) return
        visible = true
        minimized = false
        Qt.callLater(function() {
            const nativeWindow = window.contentItem.Window.window
            if (nativeWindow) {
                nativeWindow.raise()
                nativeWindow.requestActivate()
            }
            if (projects.length) projectList.forceActiveFocus()
            else browseButton.forceActiveFocus()
        })
    }

    function chooseFolder(url) {
        try {
            const stored = Paths.storedPath(url, Quickshell.env("HOME"))
            selectedProject = Paths.absolutePath(stored, Quickshell.env("HOME"))
            errorText = ""
            openButton.forceActiveFocus()
        } catch (error) {
            errorText = error.message
        }
    }

    onClosed: hidePicker()

    Process {
        id: helper
        stdout: StdioCollector { id: helperOutput }
        stderr: StdioCollector { id: helperError }
        onExited: (exitCode, exitStatus) => {
            try {
                const result = JSON.parse(helperOutput.text)
                if (!result.ok || exitCode !== 0 || exitStatus !== 0)
                    throw new Error(result.error || "Oceanus launcher failed")
                if (result.focused || result.launched) {
                    if (result.warning) {
                        errorText = result.warning
                        presentPicker()
                    } else hidePicker()
                    return
                }
                projects = result.projects || []
                selectedProject = projects.length ? projects[0] : ""
                projectList.currentIndex = projects.length ? 0 : -1
            } catch (error) {
                errorText = "Could not open Oceanus. " + (helperError.text.trim() || error.message)
            }
            presentPicker()
        }
    }

    Process {
        id: placement
        command: ["hyprctl", "eval", "hl.window_rule({name=\"fuchi-shell-oceanus-picker\","
            + "match={initial_title=\"^Fuchi-shell Oceanus$\"},float=true,center=true,"
            + "size={\"min(720,monitor_w*0.9)\",\"min(540,monitor_h*0.9)\"}})"]
        stdout: StdioCollector { id: placementOutput }
        stderr: StdioCollector { id: placementError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0 || placementOutput.text.trim() !== "ok")
                errorText = "Could not position the project picker. " + placementError.text.trim()
            activatePicker()
        }
    }

    FolderDialog {
        id: folderDialog
        objectName: "oceanusFolderDialog"
        parentWindow: window.contentItem.Window.window
        title: "Choose an Oceanus project"
        currentFolder: Paths.fileUrl(window.selectedProject || Quickshell.env("HOME"), Quickshell.env("HOME"))
        onAccepted: window.chooseFolder(selectedFolder)
    }

    Shortcut {
        sequences: [StandardKey.Close, "Escape"]
        enabled: window.visible && !folderDialog.visible
        onActivated: window.hidePicker()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Config.gap.xxl
        spacing: Config.gap.md

        Text {
            text: "New Oceanus conversation"
            color: Colors.textStrong
            font { family: Settings.fontFamily; pixelSize: Config.type.xl; bold: true }
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        Text {
            text: "Choose the project this conversation will work in."
            color: Colors.subtext
            font { family: Settings.fontFamily; pixelSize: Config.type.sm }
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        ListView {
            id: projectList
            objectName: "oceanusProjects"
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: window.projects
            spacing: Config.gap.xs
            clip: true
            enabled: !window.busy
            keyNavigationEnabled: true
            onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < window.projects.length)
                    window.selectedProject = window.projects[currentIndex]
            }
            Keys.onReturnPressed: if (window.selectedProject) window.request("launch")
            Keys.onEnterPressed: if (window.selectedProject) window.request("launch")
            ScrollBar.vertical: ScrollBar {}
            ScrollWheel { view: projectList }
            delegate: ItemDelegate {
                required property string modelData
                required property int index
                width: projectList.width
                padding: Config.gap.md
                contentItem: Column {
                    spacing: Config.gap.xs
                    Text {
                        width: parent.width
                        text: modelData.split("/").pop()
                        color: Colors.text
                        elide: Text.ElideRight
                        font { family: Settings.fontFamily; pixelSize: Config.type.base }
                    }
                    Text {
                        width: parent.width
                        text: modelData
                        color: Colors.subtext
                        wrapMode: Text.WrapAnywhere
                        font { family: Settings.fontFamily; pixelSize: Config.type.sm }
                    }
                }
                background: Rectangle {
                    color: window.selectedProject === modelData ? Colors.card : Colors.surface
                    radius: Config.radius.lg
                    border.width: window.selectedProject === modelData ? 1 : 0
                    border.color: Colors.accent
                }
                onClicked: {
                    projectList.currentIndex = index
                    window.selectedProject = modelData
                    projectList.forceActiveFocus()
                }
            }
            Text {
                anchors.fill: parent
                visible: !window.projects.length
                text: "No recent projects yet.\nBrowse to a folder to get started."
                verticalAlignment: Text.AlignVCenter
                color: Colors.subtext
                wrapMode: Text.WordWrap
                font { family: Settings.fontFamily; pixelSize: Config.type.base }
            }
        }
        Text {
            objectName: "oceanusSelectedProject"
            Layout.fillWidth: true
            text: window.selectedProject
            visible: text !== ""
            wrapMode: Text.WrapAnywhere
            color: Colors.text
            font { family: Settings.fontFamily; pixelSize: Config.type.sm }
        }
        Text {
            objectName: "oceanusError"
            Layout.fillWidth: true
            Layout.maximumHeight: 100
            text: window.errorText
            visible: text !== ""
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideRight
            color: Colors.error
            font { family: Settings.fontFamily; pixelSize: Config.type.sm }
        }
        RowLayout {
            Layout.fillWidth: true
            SettingsButton {
                id: browseButton
                objectName: "oceanusBrowse"
                text: "Browse…"
                enabled: !window.busy
                onClicked: folderDialog.open()
            }
            Item { Layout.fillWidth: true }
            SettingsButton { text: "Cancel"; onClicked: window.hidePicker() }
            SettingsButton {
                id: openButton
                objectName: "oceanusOpen"
                text: window.busy ? "Opening…" : "Open project"
                enabled: !window.busy && window.selectedProject !== ""
                onClicked: window.request("launch")
            }
        }
    }
}
