import QtQuick
import Quickshell
import "../"
import "../config.js" as Config

PopupWindow {
    id: preview
    property Item chip: null
    readonly property int thumbnailWidth: 320
    visible: !!chip
    grabFocus: false
    anchor.item: chip
    anchor.edges: Edges.Right
    anchor.gravity: Edges.Right
    // A negative right margin extends the anchor beyond the icon's hit area
    anchor.margins.right: -Config.gap.lg
    readonly property int verticalOffset: {
        if (!chip) return 0
        const iconCenterY = chip.mapToItem(null, 0, chip.height / 2).y
        return Math.max(0, Math.ceil(Config.gap.lg + implicitHeight / 2 - iconCenterY))
    }
    anchor.margins.top: verticalOffset
    anchor.margins.bottom: -verticalOffset
    readonly property real aspectRatio: image.status === Image.Ready
        ? image.sourceSize.width / image.sourceSize.height : 16 / 9
    readonly property int imageWidth: Math.min(thumbnailWidth, Math.round(240 * aspectRatio))
    implicitWidth: imageWidth + Config.gap.xs * 2
    implicitHeight: Math.round(imageWidth / aspectRatio) + Config.gap.xs * 2
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Colors.surface
        radius: Config.radius.md
        Image {
            id: image
            anchors.fill: parent
            anchors.margins: Config.gap.xs
            source: preview.chip ? preview.chip.snapshot : ""
            fillMode: Image.PreserveAspectFit
            cache: false
            Accessible.name: preview.chip ? "Preview of workspace " + preview.chip.modelData.name : ""
        }
        Text {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: preview.chip?.captureFailed || preview.chip?.modelData.active
                ? "Workspace preview unavailable" : "Visit this workspace to preview it"
            color: Colors.subtext
            font.family: Settings.fontFamily
            font.pixelSize: Config.type.sm
        }
    }
}
