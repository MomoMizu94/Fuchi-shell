import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import "config.js" as Config


PanelWindow {
    property var notifModel
    property bool dndEnabled: false
    visible: !dndEnabled

    // Docked into the frame's top-right corner so the first card melts into
    // both the top and right strips, and the cards below melt into the right
    // strip, via corner fillets like every other popup.
    anchors { top: true; right: true }
    margins { top: Config.frame.thin; right: Config.frame.thin }

    // Fillet clearance left of the first card and below the last — the window
    // must be larger than the column or the fillets would be clipped at the
    // surface edge. Height collapses to 1px when there are no cards so the
    // invisible surface doesn't linger as a click-eating strip.
    implicitWidth: 560 + Config.radius.fillet
    implicitHeight: column.implicitHeight > 0 ? column.implicitHeight + Config.radius.fillet : 1
    color: "transparent"

    exclusionMode: ExclusionMode.Normal

    ColumnLayout {
        id: column
        width: 560
        anchors.right: parent.right
        // No spacing: stacked cards butt together and read as one continuous
        // panel — only the stack's outer silhouette is shaped (corner dock at
        // the top, rounding + fillet at the bottom).
        spacing: 0

        Repeater {
            id: repeater
            model: notifModel
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                Timer {
                    running: card.modelData.urgency !== NotificationUrgency.Critical
                    interval: Config.notifications.timeout
                    onTriggered: card.modelData.dismiss()
                }

                Layout.fillWidth: true
                Layout.preferredHeight: layout.implicitHeight + 28
                topLeftRadius: 0
                bottomLeftRadius: card.index === repeater.count - 1 ? Config.radius.hero : 0
                topRightRadius: 0
                bottomRightRadius: 0
                color: Colors.surface

                // Urgency accent — a left-edge stripe instead of the old full
                // outline, which would have drawn a visible seam along the
                // frame-docked right edge.
                Rectangle {
                    id: urgencyStripe
                    width: 6
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    // Keep clear of the stack's shaped ends: stop above the
                    // bottom corner rounding (a straight strip would poke
                    // outside the curve) and start below the first card's
                    // frame dock at the top.
                    anchors.topMargin: card.index === 0 ? Config.radius.hero : 0
                    anchors.bottomMargin: card.bottomLeftRadius
                    color: card.modelData.urgency === NotificationUrgency.Critical
                        ? Colors.error : Colors.border
                }

                // Concave fillets melting the card's right corners into the
                // frame strip it docks against. The first card sits flush in
                // the frame's top-right corner, so instead of a fillet above
                // its right edge it gets one left of its top edge, melting
                // into the top strip (same geometry as Dashboard's).
                CornerFillet {
                    visible: card.index > 0
                    anchors.right: parent.right
                    anchors.bottom: parent.top
                    solidCorner: "bottomRight"
                }
                CornerFillet {
                    visible: card.index === 0
                    anchors.right: parent.left
                    anchors.top: parent.top
                    solidCorner: "topRight"
                }
                CornerFillet {
                    anchors.right: parent.right
                    anchors.top: parent.bottom
                    solidCorner: "topRight"
                }

                RowLayout {
                    id: layout
                    anchors.fill: parent
                    anchors.margins: Config.gap.md
                    anchors.leftMargin: Config.gap.md + urgencyStripe.width
                    spacing: Config.gap.md

                    Item {
                        Layout.preferredWidth: 132
                        Layout.preferredHeight: 132
                        Layout.alignment: Qt.AlignTop

                        // Notification image
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            visible: card.modelData.image !== ""
                            source: card.modelData.image
                        }

                        // Fallback: Application icon
                        IconImage {
                            anchors.fill: parent
                            visible: card.modelData.image === "" && card.modelData.appIcon !== ""
                            source: Quickshell.iconPath(card.modelData.appIcon)
                        }
                    }

                    Component.onCompleted: {
                    console.log("=== Notification ===")
                    console.log("image:", modelData.image)
                    console.log("appIcon:", modelData.appIcon)
                    console.log("desktopEntry:", modelData.desktopEntry)
                    console.log("appName:", modelData.appName)
                    console.log("summary:", modelData.summary)
                }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.gap.xs

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.lg
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: card.modelData.dismiss()
                }
            }
        }
    }
}
