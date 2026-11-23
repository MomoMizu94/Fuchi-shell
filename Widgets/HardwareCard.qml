import QtQuick
import QtQuick.Controls as Controls
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
            font.family: Settings.fontFamily
            font.pixelSize: Config.type.label
            font.bold: true
            font.letterSpacing: 1.5
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            uniformCellSizes: true
            spacing: Config.gap.lg

            Repeater {
                model: [
                    { name: "CPU", icon: "", color: Colors.cpu },
                    { name: "GPU", icon: "󰾲", color: Colors.gpu },
                    { name: "RAM", icon: "󰘚", color: Colors.ram },
                    { name: "Disk", icon: "", color: Colors.accent },
                ]
                delegate: ColumnLayout {
                    id: metric
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Config.gap.xs

                    // Read live value directly from dashboard by index
                    property real value: index === 0 ? dashboard.cpuValue
                                       : index === 1 ? dashboard.gpuValue
                                       : index === 2 ? dashboard.ramValue
                                       : dashboard.diskValue

                    readonly property string detail: {
                        if (index < 2) {
                            const temperature = index === 0 ? dashboard.cpuTemp : dashboard.gpuTemp
                            return temperature ? Math.round(temperature) + " °C" : "Temperature unavailable"
                        }
                        const used = index === 2 ? dashboard.ramUsedGb : dashboard.diskUsedGb
                        const total = index === 2 ? dashboard.ramTotalGb : dashboard.diskTotalGb
                        const digits = index === 2 ? 1 : 0
                        return total > 0 ? used.toFixed(digits) + " / " + total.toFixed(digits) + " GiB" : "Capacity unavailable"
                    }

                    HoverHandler { id: hover }
                    Controls.ToolTip {
                        parent: metric
                        x: {
                            const cursorX = hover.point.scenePosition.x
                            const rightLimit = metric.Window.width - margins - implicitWidth
                            const windowX = Math.max(margins, Math.min(cursorX + Config.gap.md, rightLimit))
                            return hover.point.position.x + windowX - cursorX
                        }
                        y: hover.point.scenePosition.y + Config.gap.md + implicitHeight <= metric.Window.height - margins
                            ? hover.point.position.y + Config.gap.md
                            : hover.point.position.y - Config.gap.md - implicitHeight
                        visible: hover.hovered && metric.visible
                        delay: 350
                        text: metric.modelData.name + " · " + metric.detail
                        font.family: Settings.fontFamily
                        font.pixelSize: Config.type.sm
                        palette.toolTipText: Colors.text
                        background: Rectangle { radius: Config.radius.md; color: Colors.surface }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle { anchors.fill: parent; radius: Config.radius.sm; color: Qt.rgba(0,0,0,0.1) }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(0, parent.height * metric.value / 100)
                            radius: Config.radius.sm
                            color: modelData.color
                            Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Config.gap.sm
                        text: Math.round(metric.value) + "%"
                        color: Colors.text
                        font.family: Settings.fontFamily
                        font.pixelSize: Config.type.md
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: metric.modelData.icon
                        color: metric.modelData.color
                        font.family: Settings.fontFamily
                        font.pixelSize: Config.type.display
                    }
                }
            }
        }
    }
}
