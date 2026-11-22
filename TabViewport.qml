import QtQuick
import QtQuick.Controls.Basic as Controls

Flickable {
    id: viewport
    objectName: "dashboardTabViewport"
    property real minimumPageWidth: 0
    required property Item availableArea
    width: availableArea.width
    height: availableArea.height
    contentWidth: Math.max(width, minimumPageWidth)
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height || contentWidth > width
    clip: true

    ScrollWheel { view: viewport }
    Controls.ScrollBar.vertical: Controls.ScrollBar {}
    Controls.ScrollBar.horizontal: Controls.ScrollBar {}
}
