import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import "../"

Flickable {
    id: viewport
    default property alias rows: column.data
    property alias spacing: column.spacing
    implicitHeight: column.implicitHeight
    contentHeight: column.implicitHeight
    contentWidth: width
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    clip: true

    function reveal(row) {
        if (!row) return
        column.ensurePolished()
        const top = row.mapToItem(contentItem, 0, 0).y
        if (top < contentY) contentY = top
        else if (top + row.height > contentY + height)
            contentY = top + row.height - height
        returnToBounds()
    }

    ScrollWheel { view: viewport }
    Controls.ScrollBar.vertical: Controls.ScrollBar {}
    ColumnLayout {
        id: column
        width: viewport.width
    }
}
