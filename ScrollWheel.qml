import QtQuick
import "config.js" as Config

WheelHandler {
    // Flickable sends declared children to its moving contentItem. Attach to
    // the viewport explicitly so the handler stays under the pointer.
    required property Flickable view
    property bool horizontal: false
    property real step: Config.scrolling.wheelStep
    parent: view
    target: view
    // Qt can classify synthesized mouse-wheel events as touchpad input.
    // Accept both so those events also reach the configured wheel step.
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    signal unhandledWheel(var event)

    function scroll(event, preferPixels = false) {
        if (!view || !view.interactive
                || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return false
        const pixels = horizontal ? (event.pixelDelta.x || event.pixelDelta.y) : event.pixelDelta.y
        const angle = horizontal ? (event.angleDelta.x || event.angleDelta.y) : event.angleDelta.y
        // Wayland mouse wheels can report both deltas. Rotation controls the
        // mouse step; pixel-only input keeps its supplied distance.
        const distance = preferPixels && pixels ? pixels : angle ? angle / 120 * step : pixels
        if (!distance) return false
        const start = horizontal ? view.originX : view.originY
        const extent = horizontal ? view.contentWidth - view.width : view.contentHeight - view.height
        const position = horizontal ? view.contentX : view.contentY
        const next = Math.max(start, Math.min(start + Math.max(0, extent), position - distance))
        if (next === position) return false
        view.cancelFlick()
        if (horizontal) view.contentX = next
        else view.contentY = next
        return true
    }

    onWheel: event => {
        event.accepted = scroll(event)
        if (!event.accepted) unhandledWheel(event)
    }
}
