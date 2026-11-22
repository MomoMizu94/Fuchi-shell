import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

// Overview tab card: Wi-Fi/Bluetooth/DND/night-light toggle tiles
Rectangle {
    id: toggles
    required property var dashboard
    readonly property color activeFill: Qt.alpha(Colors.accent, 0.18)
    Layout.fillWidth: true
    implicitHeight: quicktoggleContent.implicitHeight + 24
    radius: Config.radius.xl
    color: Colors.card

    ColumnLayout {
        id: quicktoggleContent
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Config.gap.md
        spacing: Config.gap.sm

        Text {
            text: "QUICK TOGGLES"
            color: Colors.subtext
            font.family: Settings.fontFamily
            font.pixelSize: Config.type.label
            font.bold: true
            font.letterSpacing: 1.5
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 6

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 68; radius: Config.radius.lg
                color: dashboard.wifiEnabled ? toggles.activeFill : Colors.inset
                ColumnLayout { anchors.centerIn: parent; spacing: Config.gap.xs
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰤨"
                        color: dashboard.wifiEnabled ? Colors.accent : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.xl }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Wi-Fi"
                        color: dashboard.wifiEnabled ? Colors.text : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.sm }
                }
                MouseArea { anchors.fill: parent; onClicked: dashboard.toggleWifi() }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 68; radius: Config.radius.lg
                color: dashboard.bluetoothEnabled ? toggles.activeFill : Colors.inset
                ColumnLayout { anchors.centerIn: parent; spacing: Config.gap.xs
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰂯"
                        color: dashboard.bluetoothEnabled ? Colors.accent : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.xl }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Bluetooth"
                        color: dashboard.bluetoothEnabled ? Colors.text : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.sm }
                }
                MouseArea { anchors.fill: parent; onClicked: dashboard.toggleBluetooth() }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 68; radius: Config.radius.lg
                color: dashboard.dndEnabled ? toggles.activeFill : Colors.inset
                ColumnLayout { anchors.centerIn: parent; spacing: Config.gap.xs
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰍷"
                        color: dashboard.dndEnabled ? Colors.accent : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.xl }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "DND"
                        color: dashboard.dndEnabled ? Colors.text : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.sm }
                }
                MouseArea { anchors.fill: parent; onClicked: dashboard.dndEnabled = !dashboard.dndEnabled }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 68; radius: Config.radius.lg
                color: dashboard.nightEnabled ? toggles.activeFill : Colors.inset
                ColumnLayout { anchors.centerIn: parent; spacing: Config.gap.xs
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰌵"
                        color: dashboard.nightEnabled ? Colors.accent : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.xl }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Night"
                        color: dashboard.nightEnabled ? Colors.text : Colors.subtext
                        font.family: Settings.fontFamily; font.pixelSize: Config.type.sm }
                }
                MouseArea { anchors.fill: parent; onClicked: dashboard.toggleNight() }
            }
        }
    }
}
