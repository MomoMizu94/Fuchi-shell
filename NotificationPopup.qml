import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import "config.js" as Config

// The popup stack uses the sender's timeout when supplied
PanelWindow {
    id: popup
    property var notifModel
    property bool dndEnabled: false
    property string spotifyArtUrl: ""
    visible: !dndEnabled

    // Docked into the frame's top-right corner so the first card melts into
    // both the top and right strips, and the cards below melt into the right
    // strip, via corner fillets like every other popup
    anchors { top: true; right: true }
    margins { top: Config.frame.thin; right: Config.frame.thin }

    // Fillet clearance left of the first card and below the last — the window
    // must be larger than the column or the fillets would be clipped at the
    // surface edge. Height collapses to 1px when there are no cards so the
    // invisible surface doesn't linger as a click-eating strip
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
        // the top, rounding + fillet at the bottom)
        spacing: 0

        Repeater {
            id: repeater
            model: notifModel
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property string imageSource: modelData.image
                    ? modelData.image.toString()
                    : ((modelData.appName || "").toLowerCase() === "spotify"
                        ? popup.spotifyArtUrl : "")

                Timer {
                    readonly property int requestedTimeout: card.modelData.expireTimeout ?? -1
                    interval: requestedTimeout < 0 ? Settings.notificationTimeout : requestedTimeout
                    running: interval > 0 && (requestedTimeout > 0 || card.modelData.urgency !== NotificationUrgency.Critical)
                    onTriggered: card.modelData.expire()
                }

                Layout.fillWidth: true
                Layout.preferredHeight: media.visible ? 160 : 104
                topLeftRadius: 0
                bottomLeftRadius: card.index === repeater.count - 1 ? Config.radius.hero : 0
                topRightRadius: 0
                bottomRightRadius: 0
                color: Colors.surface

                // Urgency accent — a left-edge stripe instead of the old full
                // outline, which would have drawn a visible seam along the
                // frame-docked right edge
                Rectangle {
                    id: urgencyStripe
                    width: 6
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    anchors.topMargin: Config.gap.sm
                    anchors.bottomMargin: Math.max(Config.gap.sm, card.bottomLeftRadius)
                    radius: Config.radius.xs
                    color: card.modelData.urgency === NotificationUrgency.Critical
                        ? Colors.error : Colors.border
                }

                // Curves the card's right corners inward so they blend into
                // the frame strip it docks against. The first card sits flush
                // in the frame's top-right corner, so instead of curving above
                // its right edge it curves left of its top edge, blending into
                // the top strip instead (same geometry as Dashboard's)
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
                    anchors.fill: parent
                    anchors.margins: Config.gap.md
                    anchors.leftMargin: Config.gap.md + urgencyStripe.width
                    spacing: Config.gap.md

                    Item {
                        id: media
                        Layout.preferredWidth: 132
                        Layout.preferredHeight: 132
                        visible: previewImage.available || appIcon.available

                        Image {
                            id: previewImage
                            anchors.fill: parent
                            readonly property bool available: source.toString() !== "" && status !== Image.Error
                            visible: available
                            source: card.imageSource
                            fillMode: Image.PreserveAspectFit
                        }

                        IconImage {
                            id: appIcon
                            anchors.centerIn: parent
                            readonly property string icon: card.modelData.appIcon || ""
                            readonly property bool localFile: icon.startsWith("/") || icon.startsWith("file:")
                            implicitSize: localFile ? 132 : 64
                            readonly property bool available: source.toString() !== "" && status !== Image.Error
                            visible: !previewImage.available && available
                            source: {
                                if (!icon) return ""
                                if (localFile) return Qt.resolvedUrl(icon)
                                return Quickshell.iconPath(icon, true)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Config.gap.xs

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: card.modelData.body ? 1 : 2
                            color: Colors.text
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.lg
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            color: Colors.subtext
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.base
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
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
