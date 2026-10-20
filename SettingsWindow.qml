import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "config.js" as Config

FloatingWindow {
    id: window
    title: "Fuchi-shell settings"
    visible: false
    implicitWidth: 1435
    implicitHeight: 1505
    minimumSize: Qt.size(520, 420)
    color: Colors.surface
    property bool openRequested: false
    property string placementError: ""

    // A regular Wayland toplevel needs a compositor rule to start floating.
    // Apply the named rule before mapping. An explicit size also prevents
    // Hyprland's empty-workspace size from overriding the preferred QML size.
    Process {
        id: placementRule
        command: ["hyprctl", "eval",
            "hl.window_rule({"
            + "name=\"fuchi-shell-settings\","
            + "match={initial_title=\"^Fuchi-shell settings$\"},"
            + "float=true,center=true,"
            + "size={\"min(" + window.implicitWidth + ",monitor_w*0.9)\","
            + "\"min(" + window.implicitHeight + ",monitor_h*0.9)\"}})"]
        stdout: StdioCollector { id: ruleOutput }
        stderr: StdioCollector { id: ruleError }
        onExited: (exitCode, exitStatus) => {
            window.placementError = ""
            if (exitCode !== 0 || exitStatus !== 0 || ruleOutput.text.trim() !== "ok") {
                window.placementError = "Could not set settings window placement. "
                    + (ruleError.text.trim() || ruleOutput.text.trim() || "Check that Hyprland is running.")
            }
            if (window.openRequested) {
                window.visible = true
                window.activateWindow()
            }
        }
    }

    onVisibleChanged: if (!visible) openRequested = false
    // Quickshell 0.3.2 keeps its requested visibility after a native close.
    // Clear it explicitly so the next true assignment can show the window.
    onClosed: hideSettings()

    function showSettings() {
        if (!visible) {
            fullscreen = false
            maximized = false
        }
        openRequested = true
        if (visible || !Quickshell.env("WAYLAND_DISPLAY")) {
            visible = true
            activateWindow()
        } else if (!placementRule.running) {
            placementRule.running = true
        }
    }

    function hideSettings() {
        openRequested = false
        visible = false
    }

    function activateWindow() {
        minimized = false
        Qt.callLater(function() {
            const nativeWindow = window.contentItem.Window.window
            if (nativeWindow) {
                nativeWindow.raise()
                nativeWindow.requestActivate()
            }
        })
    }

    component SectionHeading: ColumnLayout {
        required property string title
        Layout.fillWidth: true
        Layout.topMargin: Config.gap.lg
        spacing: Config.gap.sm
        Label {
            text: parent.title
            font.pixelSize: Config.type.lg
            font.bold: true
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colors.border
        }
    }

    component NumberPreference: SettingsRow {
        id: numberRow
        required property int minimum
        required property int maximum
        property int step: 1
        property string unit: ""
        controls: [
            SpinBox {
                objectName: numberRow.settingKey + "Control"
                Layout.preferredWidth: 180
                from: numberRow.minimum
                to: numberRow.maximum
                stepSize: numberRow.step
                value: Settings.value(numberRow.settingKey) || 0
                editable: true
                Accessible.name: numberRow.title
                onValueModified: Settings.setValue(numberRow.settingKey, value)
            },
            Label { text: numberRow.unit }
        ]
    }

    FolderDialog {
        id: folderDialog
        objectName: "wallpaperFolderDialog"
        parentWindow: window.contentItem.Window.window
        title: "Choose wallpaper folder"
        currentFolder: Settings.fileUrl(Settings.wallpaperFolder)
        onAccepted: Settings.setPath("wallpaperFolder", selectedFolder)
    }

    FileDialog {
        id: imageDialog
        objectName: "profilePictureDialog"
        parentWindow: window.contentItem.Window.window
        title: "Choose profile picture"
        currentFolder: Settings.fileUrl("Pictures")
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif)", "All files (*)"]
        fileMode: FileDialog.OpenFile
        onAccepted: Settings.setPath("profilePic", selectedFile)
    }

    Shortcut {
        sequences: [StandardKey.Close]
        enabled: window.visible
        onActivated: window.hideSettings()
    }

    Pane {
        objectName: "settingsContent"
        anchors.fill: parent
        padding: Config.gap.xxl
        font.family: Settings.fontFamily
        font.pixelSize: Config.type.sm
        palette.window: Colors.surface
        palette.windowText: Colors.text
        palette.base: Colors.inset
        palette.text: Colors.text
        palette.button: Colors.card
        palette.buttonText: Colors.text
        palette.highlight: Colors.accent
        palette.highlightedText: Colors.contrastText
        palette.mid: Colors.border
        palette.dark: Colors.border
        palette.light: Colors.card
        background: Rectangle { color: Colors.surface }

        ColumnLayout {
            anchors.fill: parent
            spacing: Config.gap.lg

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: Config.gap.xs
                    Label {
                        text: "Settings"
                        font.pixelSize: Config.type.xl
                        font.bold: true
                    }
                    Label {
                        text: "Changes apply immediately."
                        color: Colors.subtext
                        font.pixelSize: Config.type.label
                    }
                }
                Item { Layout.fillWidth: true }
                SettingsButton {
                    text: "Close"
                    onClicked: window.hideSettings()
                }
            }

            Label {
                Layout.fillWidth: true
                visible: window.placementError !== ""
                text: window.placementError
                color: Colors.error
                wrapMode: Text.Wrap
            }

            Label {
                Layout.fillWidth: true
                visible: Settings.errorText !== ""
                text: Settings.errorText
                color: Colors.error
                wrapMode: Text.Wrap
            }

            ScrollView {
                id: scroll
                objectName: "settingsScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: Config.gap.xl

                    SectionHeading { title: "Appearance"; Layout.topMargin: 0 }

                    SettingsRow {
                        title: "Font"
                        description: "Choose a Nerd Font so shell icons display correctly. Type a font name to find it."
                        settingKey: "fontFamily"
                        controls: [
                            ComboBox {
                                id: fontPicker
                                objectName: "fontFamilyControl"
                                Layout.fillWidth: true
                                model: Settings.fontFamilies
                                currentIndex: model.indexOf(Settings.fontFamily)
                                editable: true
                                selectTextByMouse: true
                                Accessible.name: "Shell font"
                                onActivated: index => Settings.setValue("fontFamily", model[index])
                                onAccepted: Settings.setValue("fontFamily", editText)
                            }
                        ]
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: fontPreview.implicitHeight + Config.gap.lg * 2
                        color: Colors.inset
                        radius: Config.radius.lg
                        ColumnLayout {
                            id: fontPreview
                            anchors.fill: parent
                            anchors.margins: Config.gap.lg
                            spacing: Config.gap.sm
                            Label {
                                Layout.fillWidth: true
                                text: "The quick brown fox 0123456789"
                                font.family: Settings.fontFamilies.includes(fontPicker.editText)
                                    ? fontPicker.editText : Settings.fontFamily
                                font.pixelSize: Config.type.base
                                wrapMode: Text.Wrap
                            }
                            Label {
                                text: "󰕮   󰤨   󰂯   󰋋   󰃭"
                                font.family: Settings.fontFamilies.includes(fontPicker.editText)
                                    ? fontPicker.editText : Settings.fontFamily
                                font.pixelSize: Config.type.xl
                                color: Colors.accent
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: !Settings.fontFamilies.includes(Settings.value("fontFamily"))
                        text: "The saved font is not installed. Using the default font until you choose another."
                        color: Colors.warn
                        wrapMode: Text.Wrap
                    }

                    SettingsRow {
                        title: "Profile picture"
                        description: "Use an absolute path or a path relative to your home folder."
                        settingKey: "profilePic"
                        controls: [
                            TextField {
                                objectName: "profilePicControl"
                                Layout.fillWidth: true
                                text: Settings.profilePic
                                placeholderText: "No profile picture"
                                selectByMouse: true
                                Accessible.name: "Profile picture path"
                                onEditingFinished: Settings.setPath("profilePic", text.trim())
                            },
                            SettingsButton { text: "Browse"; onClicked: imageDialog.open() }
                        ]
                    }

                    SettingsRow {
                        title: "Layout labels"
                        description: "Choose how tiling layouts appear in the sidebar and layout menu."
                        settingKey: "layoutIcons"
                        controls: [
                            ComboBox {
                                objectName: "layoutIconsControl"
                                Layout.fillWidth: true
                                model: ["ASCII symbols", "Nerd Font icons"]
                                currentIndex: Settings.layoutIcons ? 1 : 0
                                Accessible.name: "Layout label style"
                                onActivated: index => Settings.setValue("layoutIcons", index === 1)
                            }
                        ]
                    }

                    Repeater {
                        model: [
                            { key: "animationSlide", title: "Dashboard animation" },
                            { key: "animationPopup", title: "Menu animation" },
                            { key: "animationTabSlide", title: "Tab animation" }
                        ]
                        delegate: NumberPreference {
                            required property var modelData
                            title: modelData.title
                            description: "Set to 0 to turn this animation off."
                            settingKey: modelData.key
                            minimum: 0
                            maximum: 2000
                            step: 50
                            unit: "milliseconds"
                        }
                    }

                    SectionHeading { title: "Notifications" }

                    NumberPreference {
                        title: "Popup timeout"
                        description: "How long ordinary notifications stay visible. Critical notifications stay until dismissed."
                        settingKey: "notificationTimeout"
                        minimum: 1000
                        maximum: 60000
                        step: 1000
                        unit: "milliseconds"
                    }

                    NumberPreference {
                        title: "History limit"
                        description: "Maximum notifications kept in history. Lowering this removes older entries. Set to 0 to keep none."
                        settingKey: "historyLimit"
                        minimum: 0
                        maximum: 2000
                        step: 10
                        unit: "notifications"
                    }

                    SectionHeading { title: "Launcher" }

                    SettingsRow {
                        title: "Wallpaper folder"
                        description: "Where the >wallpaper command looks for images."
                        settingKey: "wallpaperFolder"
                        controls: [
                            TextField {
                                objectName: "wallpaperFolderControl"
                                Layout.fillWidth: true
                                text: Settings.wallpaperFolder
                                selectByMouse: true
                                Accessible.name: "Wallpaper folder path"
                                onEditingFinished: Settings.setPath("wallpaperFolder", text.trim())
                            },
                            SettingsButton { text: "Browse"; onClicked: folderDialog.open() }
                        ]
                    }

                    NumberPreference {
                        title: "Visible results"
                        description: "Maximum rows shown before scrolling. Fewer rows may fit on a small screen."
                        settingKey: "launcherRows"
                        minimum: 1
                        maximum: 20
                        unit: "rows"
                    }

                    SectionHeading { title: "Sound" }

                    NumberPreference {
                        title: "Maximum volume"
                        description: "Highest volume selectable in the shell mixer. Keyboard shortcuts keep their own limits."
                        settingKey: "volumeLimit"
                        minimum: 100
                        maximum: 200
                        step: 5
                        unit: "%"
                    }

                    SectionHeading { title: "Shell" }

                    Label {
                        Layout.fillWidth: true
                        text: "Reload the shell configuration. Temporary state such as notification history may reset."
                        font.pixelSize: Config.type.label
                        color: Colors.subtext
                        wrapMode: Text.Wrap
                    }
                    SettingsButton {
                        objectName: "reloadShellButton"
                        text: Settings.reloadPending ? "Reloading..." : "Reload shell"
                        enabled: !Settings.reloadPending
                        onClicked: {
                            // Commit a text field before deciding which writes to wait for.
                            forceActiveFocus()
                            Qt.callLater(Settings.requestReload)
                        }
                    }
                    Item { implicitHeight: Config.gap.sm }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: !Settings.ready ? "Saved settings could not be loaded."
                        : Settings.saving || Settings.dirty ? "Saving changes..." : "Changes saved"
                    font.pixelSize: Config.type.label
                    color: Colors.subtext
                    wrapMode: Text.Wrap
                }
                SettingsButton {
                    text: "Retry saving"
                    visible: Settings.ready && Settings.dirty && Settings.errorText !== ""
                    enabled: !Settings.saving
                    onClicked: Settings.save()
                }
            }
        }
    }
}
