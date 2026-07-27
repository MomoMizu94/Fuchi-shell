import Quickshell
import Quickshell.Wayland
import QtQuick
import "config.js" as Config

// Draws the whole frame as a single shape: full-screen rect minus a
// rounded-rect hole for the content area. One hole, one radius computation —
// no per-corner mapping to get backwards.
PanelWindow {
    id: root
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    signal hoverOpenRequested()
    signal launcherHoverRequested()

    // Continuous (not fire-once) hover state — VolumeMenu/Dashboard bind to
    // these directly so they can auto-close shortly after the cursor leaves,
    // unlike the signal-based zones below whose targets only ever open.
    property bool volumeHovered: false
    property bool dashboardHovered: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    readonly property real holeX: Config.frame.thick
    readonly property real holeY: Config.frame.thin
    readonly property real holeWidth: width - Config.frame.thick - Config.frame.thin
    readonly property real holeHeight: height - Config.frame.thin * 2
    readonly property real holeRadius: 8

    // Without this, the surface would capture clicks over the whole screen,
    // including the transparent hole — verified live (mouse became unusable
    // the moment this window appeared). Subtract the hole from the hit area
    // so clicks pass through to windows underneath; only the drawn frame
    // itself intercepts input.
    mask: Region {
        x: 0
        y: 0
        width: root.width
        height: root.height

        Region {
            intersection: Intersection.Subtract
            x: root.holeX
            y: root.holeY
            width: root.holeWidth
            height: root.holeHeight
            radius: root.holeRadius
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            // NOTE: ctx.fill('evenodd') is broken on this Qt build — the fillRule
            // argument is silently ignored and it always fills solid (verified via
            // an isolated offscreen test). Punch the hole with destination-out
            // compositing instead, which is unaffected by winding rules.
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.globalCompositeOperation = "source-over"
            ctx.fillStyle = "" + Colors.surface
            ctx.fillRect(0, 0, width, height)

            var x0 = root.holeX, y0 = root.holeY
            var x1 = x0 + root.holeWidth, y1 = y0 + root.holeHeight
            var r = root.holeRadius
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = "black"
            ctx.beginPath()
            ctx.moveTo(x0 + r, y0)
            ctx.lineTo(x1 - r, y0)
            ctx.arcTo(x1, y0, x1, y0 + r, r)
            ctx.lineTo(x1, y1 - r)
            ctx.arcTo(x1, y1, x1 - r, y1, r)
            ctx.lineTo(x0 + r, y1)
            ctx.arcTo(x0, y1, x0, y1 - r, r)
            ctx.lineTo(x0, y0 + r)
            ctx.arcTo(x0, y0, x0 + r, y0, r)
            ctx.closePath()
            ctx.fill()
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // Top-center hover hot-zone that opens the Dashboard. Must stay within the
    // top border strip (y: 0..Config.frame.thin) — that's the only part of this
    // surface not subtracted by `mask` above, so it's the only place pointer
    // events actually reach us rather than passing through to windows below.
    Item {
        width: 600
        height: Config.frame.thin
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0

        HoverHandler {
            onHoveredChanged: {
                root.dashboardHovered = hovered
                if (hovered) root.hoverOpenRequested()
            }
        }
    }

    // Bottom-center hover hot-zone that spawns the app launcher. Same reasoning
    // as the top zone above — the bottom border strip (y: height-thin..height)
    // is the only other part of this surface `mask` doesn't subtract.
    Item {
        width: 600
        height: Config.frame.thin
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - Config.frame.thin

        HoverHandler {
            onHoveredChanged: if (hovered) root.launcherHoverRequested()
        }
    }

    // Right-center hover hot-zone that spawns the volume menu. Same reasoning
    // as the other two zones — the right border strip (x: width-thin..width)
    // is the last part of this surface `mask` doesn't subtract.
    Item {
        width: Config.frame.thin
        height: 600
        anchors.verticalCenter: parent.verticalCenter
        x: root.width - Config.frame.thin

        HoverHandler {
            onHoveredChanged: root.volumeHovered = hovered
        }
    }
}
