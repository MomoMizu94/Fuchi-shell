import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Effects
import "../"
import "../config.js" as Config

// Overview tab card: profile picture + OS/kernel/WM/uptime stats
Rectangle {
    required property var dashboard
    Layout.preferredWidth: 400
    radius: Config.radius.xl
    color: Colors.card

    RowLayout {
        id: systeminfoContent
        anchors.fill: parent
        anchors.margins: Config.gap.md
        spacing: Config.gap.lg

        // Profile picture — path is configurable (Config.systemInfo.profilePic);
        // falls back to an icon when image is not found via path
        Item {
            width: 140; height: 140

            Image {
                id: profileImg
                anchors.fill: parent
                source: "file://" + Quickshell.env("HOME") + "/" + Config.systemInfo.profilePic
                fillMode: Image.PreserveAspectCrop
                layer.enabled: true
                visible: false
            }

            Rectangle {
                id: circleMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                source: profileImg
                anchors.fill: profileImg
                maskEnabled: true
                maskSource: circleMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                visible: profileImg.status === Image.Ready
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Colors.border
                visible: profileImg.status !== Image.Ready
                Text {
                    anchors.centerIn: parent
                    text: "󰀄"
                    color: Colors.card
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.display
                }
            }
        }

        // Stats column
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Config.gap.sm

            Repeater {
                model: [
                    { icon: "󰣇", value: dashboard.sysOs     },
                    { icon: "󰌢", value: dashboard.sysKernel },
                    { icon: "󱂬", value: dashboard.sysWm     },
                    { icon: "󰅐", value: "up " + dashboard.sysUptime },
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Config.gap.sm

                    Text {
                        text: modelData.icon
                        color: Colors.accent
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.md
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: modelData.value || "…"
                        color: Colors.border
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.base
                        font.bold: true
                    }
                }
            }
        }
    }
}
