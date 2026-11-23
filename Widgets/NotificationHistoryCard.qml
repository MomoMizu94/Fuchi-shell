import QtQuick
import QtQuick.Controls.Basic as Controls
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
        color: Colors.text
        font.family: Settings.fontFamily
        font.pixelSize: Config.type.lg                            
        font.bold: true
    }
    Text {
        text: "Clear all"
        visible: dashboard.historyModel && dashboard.historyModel.count > 0
        color: Colors.error
        font.family: Settings.fontFamily
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
    color: Colors.subtext
    font.family: Settings.fontFamily
    font.pixelSize: Config.type.md
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}

Flickable {
    id: historyScroll
    ScrollWheel { view: historyScroll }
    Controls.ScrollBar.vertical: Controls.ScrollBar {}
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
                id: entry
                required property string summary
                required property string body
                required property string time
                required property string image
                required property string appIcon
                required property int index

                property bool expanded: false
                readonly property bool canExpand: expanded || titleText.truncated || bodyText.truncated
                onHeightChanged: if (expanded) Qt.callLater(revealExpandedText)

                function revealExpandedText() {
                    if (!expanded) return
                    const top = entry.mapToItem(historyScroll.contentItem, 0, 0).y
                    const bottom = top + entry.height
                    if (top < historyScroll.contentY)
                        historyScroll.contentY = top
                    else if (bottom > historyScroll.contentY + historyScroll.height)
                        historyScroll.contentY = Math.min(top, bottom - historyScroll.height)
                }

                Layout.fillWidth: true
                radius: Config.radius.xl
                color: Colors.card
                implicitHeight: nc.implicitHeight + 24

                MouseArea {
                    id: expandButton
                    anchors.fill: parent
                    enabled: entry.canExpand
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    activeFocusOnTab: enabled
                    Accessible.ignored: !enabled
                    Accessible.role: Accessible.Button
                    Accessible.name: (entry.expanded ? "Collapse " : "Expand ") + entry.summary
                    Accessible.expandable: enabled
                    Accessible.expanded: entry.expanded
                    Accessible.onPressAction: entry.expanded = !entry.expanded
                    onClicked: entry.expanded = !entry.expanded
                    Keys.onSpacePressed: entry.expanded = !entry.expanded
                    Keys.onReturnPressed: entry.expanded = !entry.expanded
                }

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
                            id: titleText
                            text: summary
                            textFormat: Text.PlainText
                            color: Colors.text
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.md
                            font.bold: true
                            wrapMode: Text.Wrap
                            maximumLineCount: entry.expanded ? undefined : (entry.body ? 1 : 2)
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            id: bodyText
                            visible: body !== ""
                            text: body
                            color: Colors.subtext
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.base
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: entry.expanded ? undefined : 2
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        spacing: Config.gap.xs
                        Text {
                            text: time
                            color: Colors.subtext 
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.sm
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: Config.gap.xs
                            Text {
                                visible: entry.canExpand
                                text: entry.expanded ? "▴" : "▾"
                                color: expandButton.containsMouse || expandButton.activeFocus ? Colors.accent : Colors.subtext
                                font.pixelSize: Config.type.sm
                                Accessible.ignored: true
                            }
                            Text {
                                text: ""
                                color: Colors.error
                                font.family: Settings.fontFamily
                                font.pixelSize: Config.type.lg
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: dashboard.historyModel.remove(entry.index, 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
}
