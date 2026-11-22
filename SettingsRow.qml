import QtQuick
import QtQuick.Layouts
import "config.js" as Config

GridLayout {
    id: row
    required property string title
    property string description: ""
    property string settingKey: ""
    property bool compactEditor: false
    property bool fullWidthEditor: false
    property alias controls: editor.data

    Layout.fillWidth: true
    Layout.maximumWidth: fullWidthEditor ? Infinity : 900
    Layout.alignment: Qt.AlignLeft
    columns: !fullWidthEditor && width >= 720 ? 2 : 1
    columnSpacing: Config.gap.xxl
    rowSpacing: Config.gap.sm

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
    RowLayout {
        Layout.fillWidth: row.columns === 1
        Layout.preferredWidth: row.columns === 2 ? 390 : -1
        enabled: Settings.ready && !Settings.reloadPending
        spacing: Config.gap.sm

        RowLayout {
            id: editor
            Layout.fillWidth: !row.compactEditor
            spacing: Config.gap.sm
        }
        SettingsButton {
            text: "Reset"
            visible: Settings.ready && Settings.isOverridden(row.settingKey)
            Accessible.name: "Reset " + row.title.toLowerCase()
            onClicked: Settings.reset(row.settingKey)
        }
        Item { Layout.fillWidth: true; visible: row.compactEditor }
    }
}
