import QtQuick
import "config.js" as Config

// Concave quarter-circle fillet placed just outside a popup panel's
// frame-side corners so the panel appears to curve outward and melt into the
// screen frame instead of butting against it at a right angle.
//
// The shape is a square minus a quarter-disk: `solidCorner` names the corner
// of this square that stays solid — the tip wedged into the junction between
// the frame edge and the panel edge. The arc is centered on the opposite
// corner. Drawn with a single moveTo(tip) + arc + closePath, where both the
// implicit line into the arc start and the closing line back to the tip run
// along the square's edges.
Canvas {
    id: fillet

    // "topLeft" | "topRight" | "bottomLeft" | "bottomRight"
    property string solidCorner: "topLeft"
    property color color: Colors.surface

    width: Config.radius.fillet
    height: Config.radius.fillet

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = "" + color
        var w = width, h = height, r = Math.min(width, height)
        ctx.beginPath()
        // Canvas angles: 0 = +x, increasing toward +y (visually clockwise)
        if (solidCorner === "topLeft") {
            ctx.moveTo(0, 0)
            ctx.arc(w, h, r, Math.PI, 1.5 * Math.PI, false)
        } else if (solidCorner === "topRight") {
            ctx.moveTo(w, 0)
            ctx.arc(0, h, r, 1.5 * Math.PI, 2 * Math.PI, false)
        } else if (solidCorner === "bottomLeft") {
            ctx.moveTo(0, h)
            ctx.arc(w, 0, r, 0.5 * Math.PI, Math.PI, false)
        } else { // bottomRight
            ctx.moveTo(w, h)
            ctx.arc(0, 0, r, 0, 0.5 * Math.PI, false)
        }
        ctx.closePath()
        ctx.fill()
    }

    Component.onCompleted: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
