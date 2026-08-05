import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

// Performance tab: CPU/RAM/GPU donut gauges, per-core bars, and
// network/disk/process stats
ColumnLayout {
    id: root
    required property var dashboard

    spacing: 14

    // -- Top: CPU / RAM / GPU donut gauges --
    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        Repeater {
            model: [
                { label: "CPU", icon: "󰍛" },
                { label: "RAM", icon: "󰘚" },
                { label: "GPU", icon: "󰢮" }
            ]
            delegate: Rectangle {
                id: gaugeCard
                required property var modelData
                required property int index
                property real value: index === 0 ? dashboard.cpuValue
                                   : index === 1 ? dashboard.ramValue
                                   : dashboard.gpuValue
                property string subline: index === 0
                        ? dashboard.cpuFreqGhz.toFixed(1) + "GHz · " + Math.round(dashboard.cpuTemp) + "°C"
                    : index === 1
                        ? dashboard.ramUsedGb.toFixed(1) + " / " + Math.round(dashboard.ramTotalGb) + " GB"
                        : Math.round(dashboard.gpuTemp) + "°C · " + dashboard.gpuName

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Config.radius.xl
                color: Colors.inset

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Item {
                        id: gauge
                        property real size: Math.min(gaugeCard.width, gaugeCard.height) * 0.55
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: size
                        Layout.preferredHeight: size

                        Rectangle {
                            anchors.centerIn: parent
                            width: gauge.size * 0.78; height: width
                            radius: width / 2
                            color: Colors.onAccent
                        }

                        Canvas {
                            anchors.fill: parent
                            property real value: gaugeCard.value
                            onValueChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                var cx = width / 2, cy = height / 2
                                var lw = gauge.size * 0.11
                                var r = (gauge.size - lw) / 2
                                ctx.lineWidth = lw
                                ctx.lineCap = "round"
                                ctx.strokeStyle = Colors.subtext
                                ctx.globalAlpha = 0.35
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                ctx.stroke()
                                ctx.globalAlpha = 1.0
                                ctx.strokeStyle = Colors.accent
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, value / 100))
                                ctx.stroke()
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: -2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(gaugeCard.value)
                                color: Colors.text
                                font.family: Config.bar.fontFamily
                                font.pixelSize: gauge.size * 0.28
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "%"
                                color: Colors.subtext
                                font.family: Config.bar.fontFamily
                                font.pixelSize: gauge.size * 0.11
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        Text {
                            text: gaugeCard.modelData.icon
                            color: Colors.accent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 2
                        }
                        Text {
                            text: gaugeCard.modelData.label
                            color: Colors.accent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 2
                            font.bold: true
                            font.letterSpacing: 1.5
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: gaugeCard.subline
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.bar.fontSize - 6
                    }
                }
            }
        }
    }

    // -- Bottom: per-core bars + network/disk/process info --
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 14

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Config.radius.xl
            color: Colors.inset

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "CPU CORES"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.bar.fontSize - 6
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6

                        Repeater {
                            model: dashboard.coreLoads.length
                            delegate: Item {
                                required property int index
                                property real load: dashboard.coreLoads[index] || 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(4, parent.height * parent.load / 100)
                                    radius: Config.radius.sm
                                    color: parent.load > 66 ? Colors.error
                                         : parent.load > 33 ? Colors.accent
                                         : Colors.accent2
                                    Behavior on height {
                                        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: Math.round(root.width * 0.26)
            Layout.fillHeight: true
            radius: Config.radius.xl
            color: Colors.inset

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 0

                Repeater {
                    model: [
                        { icon: "", label: "upload" },
                        { icon: "", label: "download" },
                        { icon: "", label: "disk /" },
                        { icon: "", label: "processes" }
                    ]
                    delegate: RowLayout {
                        id: infoRow
                        required property var modelData
                        required property int index
                        property string value: index === 0 ? dashboard.netUpMbs.toFixed(1) + " MB/s"
                                             : index === 1 ? dashboard.netDownMbs.toFixed(1) + " MB/s"
                                             : index === 2 ? Math.round(dashboard.diskUsedGb) + " / " + Math.round(dashboard.diskTotalGb) + " GB"
                                             : "" + dashboard.processCount

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        Text {
                            text: infoRow.modelData.icon
                            color: Colors.accent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 4
                        }
                        Text {
                            text: infoRow.modelData.label
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 4
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: infoRow.value
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 4
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
}