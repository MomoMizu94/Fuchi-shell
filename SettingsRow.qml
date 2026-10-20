import QtQuick
import QtQuick.Layouts
import "config.js" as Config

ColumnLayout {
    id: row
    required property string title
    property string description: ""
    property string settingKey: ""
    property alias controls: editor.data
    Layout.fillWidth: true
    spacing: Config.gap.sm

    RowLayout {
        Layout.fillWidth: true
        spacing: Config.gap.md
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Config.gap.xs
            Text {
                Layout.fillWidth: true
                text: row.title
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.base
                color: Colors.text
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.description
                font.family: Settings.fontFamily
                font.pixelSize: Config.type.label
                color: Colors.subtext
                wrapMode: Text.Wrap
            }
        }
        SettingsButton {
            text: "Reset"
            enabled: Settings.ready && Settings.isOverridden(row.settingKey)
            Accessible.name: "Reset " + row.title.toLowerCase()
            onClicked: Settings.reset(row.settingKey)
        }
    }
    RowLayout {
        id: editor
        Layout.fillWidth: true
        enabled: Settings.ready && !Settings.reloadPending
        spacing: Config.gap.sm
    }
}
