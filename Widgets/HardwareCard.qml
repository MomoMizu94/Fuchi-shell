import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

// Overview tab card: CPU/GPU/RAM/disk mini fill-bars, fed by Dashboard.qml's
// perfProc (see the hardwareRefresh Timer there)
Rectangle {
    required property var dashboard
    Layout.preferredWidth: 400
    radius: Config.radius.xl
    color: Colors.card

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Config.gap.lg
        spacing: Config.gap.lg

        Text {
            text: "HARDWARE"
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.label
            font.bold: true
            font.letterSpacing: 1.5
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Config.gap.lg

            Repeater {
                model: [
                    { icon: "", color: Colors.accentAlt   },
                    { icon: "󰾲", color: Colors.accent2 },
                    { icon: "󰘚", color: Colors.accent3   },
                    { icon: "", color: Colors.accent },
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Config.gap.lg

                    // Read live value directly from dashboard by index
                    property real value: index === 0 ? dashboard.cpuValue
                                       : index === 1 ? dashboard.gpuValue
                                       : index === 2 ? dashboard.ramValue
                                       : dashboard.diskValue

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle { anchors.fill: parent; radius: Config.radius.sm; color: Qt.rgba(0,0,0,0.1) }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(0, parent.height * parent.parent.value / 100)
                            radius: Config.radius.sm
                            color: modelData.color
                            Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.icon
                        color: modelData.color
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.display
                    }
                }
            }
        }
    }
}
