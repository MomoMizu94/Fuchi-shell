import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../"
import "../config.js" as Config

// Overview tab card: scrollable notification history, backed by
// dashboard.historyModel (see shell.qml's NotificationServer)
ColumnLayout {
    required property var dashboard
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Config.gap.lg

RowLayout {
    Layout.fillWidth: true
    Text {
        Layout.fillWidth: true
        text: "Notifications"
        color: Colors.border
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.type.lg                            
        font.bold: true
    }
    Text {
        text: "Clear all"
        visible: dashboard.historyModel && dashboard.historyModel.count > 0
        color: Colors.error
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.type.base
        font.bold: true
        MouseArea {
            anchors.fill: parent
            onClicked: dashboard.historyModel.clear()
        }
    }
}

Text {
    visible: !dashboard.historyModel || dashboard.historyModel.count === 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    text: "No notifications"
    color: Colors.error
    font.family: Config.bar.fontFamily
    font.pixelSize: Config.type.md
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}

Flickable {
    Layout.fillWidth: true
    Layout.fillHeight: true
    contentHeight: notifsCol.implicitHeight
    clip: true
    visible: dashboard.historyModel && dashboard.historyModel.count > 0

    ColumnLayout {
        id: notifsCol
        width: parent.width
        spacing: Config.gap.sm

        Repeater {
            model: dashboard.historyModel
            delegate: Rectangle {
                required property string summary
                required property string body
                required property string time
                required property string image
                required property string appIcon
                required property int index

                Layout.fillWidth: true
                radius: Config.radius.xl
                color: Colors.card
                implicitHeight: nc.implicitHeight + 24

                RowLayout {
                    id: nc
                    anchors {
                        left: parent.left; right: parent.right
                        top: parent.top; margins: 12
                    }
                    spacing: Config.gap.sm

                    Item {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        Layout.alignment: Qt.AlignVCenter

                        // Notification image
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            visible: image !== ""
                            source: image
                        }

                        // Fallback: Application icon
                        IconImage {
                            anchors.fill: parent
                            visible: image === "" && appIcon !== ""
                            source: Quickshell.iconPath(appIcon)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.gap.xs
                        Text {
                            Layout.fillWidth: true
                            text: summary
                            color: Colors.border
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.md
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: body !== ""
                            text: body
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        spacing: Config.gap.xs
                        Text {
                            text: time
                            color: Colors.subtext 
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                        }
                        Text {
                            text: ""
                            color: Colors.error
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.lg
                            font.bold: true
                            Layout.alignment: Qt.AlignRight
                            MouseArea {
                                anchors.fill: parent
                                onClicked: dashboard.historyModel.remove(index, 1)
                            }
                        }
                    }
                }
            }
        }
    }
}
}
