import QtQuick
import "../"
import "../config.js" as Config

// Price chart over one symbol's OHLC series. Draws either candlesticks or a
// close-price line, and pans/zooms purely over the already-fetched array —
// nothing here triggers a refetch. Only the range presets do that.
Item {
    id: root

    // One entry from Dashboard.financeSeries: {sym,ok,name,cur,price,prev,t,o,h,l,c}
    property var series: null
    property string mode: "line"        // "candle" | "line"
    property bool interactive: false
    property bool showAxis: false

    // Viewport into `candles`. viewCount 0 means "everything".
    property int viewStart: 0
    property int viewCount: 0

    // Yahoo returns nulls inside the OHLC arrays (always on intraday ranges),
    // and drawing straight through them tears the chart — so filter once here
    // rather than guarding at every draw site.
    readonly property var candles: {
        const s = root.series
        if (!s || !s.ok || !s.t || s.t.length === 0) return []
        const out = []
        for (let i = 0; i < s.t.length; i++) {
            const o = s.o[i], h = s.h[i], l = s.l[i], c = s.c[i]
            if (o === null || h === null || l === null || c === null) continue
            if (o === undefined || h === undefined || l === undefined || c === undefined) continue
            out.push({ t: s.t[i], o: o, h: h, l: l, c: c })
        }
        return out
    }

    readonly property int count: candles.length
    readonly property int vCount: count === 0 ? 0
        : (viewCount <= 0 ? count : Math.max(1, Math.min(viewCount, count)))
    readonly property int vStart: count === 0 ? 0
        : Math.max(0, Math.min(viewStart, count - vCount))
    readonly property bool zoomed: vCount < count

    // Palette pulled out as properties so a pywal retheme repaints the canvas.
    readonly property color upColor: Colors.ok
    readonly property color downColor: Colors.error
    readonly property color axisColor: Colors.subtext

    function resetView() {
        viewStart = 0
        viewCount = 0
    }

    function priceText(v) {
        const a = Math.abs(v)
        if (a >= 1000) return v.toFixed(0)
        if (a >= 1) return v.toFixed(2)
        return v.toFixed(4)
    }

    onCandlesChanged: canvas.requestPaint()
    onVStartChanged: canvas.requestPaint()
    onVCountChanged: canvas.requestPaint()
    onModeChanged: canvas.requestPaint()
    onUpColorChanged: canvas.requestPaint()
    onDownColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.count === 0 || width <= 0 || height <= 0) return

            const gutter = root.showAxis ? 54 : 0     // right-hand price axis
            const padTop = 6
            const padBot = 6
            const plotW = width - gutter
            const plotH = height - padTop - padBot
            if (plotW <= 0 || plotH <= 0) return

            const start = root.vStart
            const n = root.vCount

            // Scale to the visible slice only, so zooming actually rescales.
            let lo = Infinity, hi = -Infinity
            for (let i = start; i < start + n; i++) {
                const c = root.candles[i]
                if (c.l < lo) lo = c.l
                if (c.h > hi) hi = c.h
            }
            if (!isFinite(lo) || !isFinite(hi)) return
            if (hi === lo) { hi = lo + (lo === 0 ? 1 : Math.abs(lo) * 0.01); }
            const pad = (hi - lo) * 0.06
            lo -= pad; hi += pad

            const slot = plotW / n
            function xAt(i) { return (i - start) * slot + slot / 2 }
            function yAt(p) { return padTop + plotH - ((p - lo) / (hi - lo)) * plotH }

            // ── gridlines + price axis ──
            ctx.lineWidth = 1
            ctx.strokeStyle = root.axisColor
            ctx.fillStyle = root.axisColor
            ctx.font = "13px '" + Config.bar.fontFamily + "'"
            ctx.textBaseline = "middle"
            const lines = 4
            for (let g = 0; g <= lines; g++) {
                const p = lo + (hi - lo) * (g / lines)
                const y = Math.round(yAt(p)) + 0.5
                ctx.globalAlpha = 0.12
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(plotW, y)
                ctx.stroke()
                if (root.showAxis) {
                    ctx.globalAlpha = 0.7
                    ctx.fillText(root.priceText(p), plotW + 6, y)
                }
            }
            ctx.globalAlpha = 1.0

            const first = root.candles[start]
            const last = root.candles[start + n - 1]
            const rising = last.c >= first.o
            const seriesColor = rising ? root.upColor : root.downColor

            // Candles collapse into a smear once they're thinner than a few px,
            // so fall back to the line renderer instead of drawing mush.
            const drawCandles = root.mode === "candle" && slot >= Config.finance.candleMinWidth

            if (drawCandles) {
                const bodyW = Math.max(1, Math.min(slot * 0.7, 14))
                for (let i = start; i < start + n; i++) {
                    const c = root.candles[i]
                    const up = c.c >= c.o
                    const col = up ? root.upColor : root.downColor
                    const x = xAt(i)

                    ctx.strokeStyle = col
                    ctx.lineWidth = Math.max(1, Math.min(2, slot * 0.12))
                    ctx.beginPath()
                    ctx.moveTo(x, yAt(c.h))
                    ctx.lineTo(x, yAt(c.l))
                    ctx.stroke()

                    const yO = yAt(c.o), yC = yAt(c.c)
                    const top = Math.min(yO, yC)
                    // A doji would otherwise vanish entirely.
                    const bh = Math.max(1, Math.abs(yC - yO))
                    ctx.fillStyle = col
                    ctx.fillRect(x - bodyW / 2, top, bodyW, bh)
                }
            } else {
                ctx.strokeStyle = seriesColor
                ctx.lineWidth = 2
                ctx.lineJoin = "round"
                ctx.beginPath()
                for (let i = start; i < start + n; i++) {
                    const x = xAt(i), y = yAt(root.candles[i].c)
                    if (i === start) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
            }

            // ── last-price marker ──
            const yLast = yAt(last.c)
            ctx.strokeStyle = seriesColor
            ctx.globalAlpha = 0.55
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, Math.round(yLast) + 0.5)
            ctx.lineTo(plotW, Math.round(yLast) + 0.5)
            ctx.stroke()
            ctx.globalAlpha = 1.0
        }
    }

    // ── pan / zoom (focused chart only) ──
    MouseArea {
        id: panArea
        anchors.fill: parent
        enabled: root.interactive && root.count > 1
        acceptedButtons: Qt.LeftButton
        cursorShape: root.interactive && root.count > 1
            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            : Qt.ArrowCursor
        preventStealing: true

        property real pressX: 0
        property int pressStart: 0

        onPressed: mouse => {
            pressX = mouse.x
            pressStart = root.vStart
            // Grab the current window explicitly: until the first drag the
            // viewport is "all candles" (viewCount 0), and panning that is a
            // no-op unless it becomes a concrete count first.
            if (root.viewCount <= 0) root.viewCount = root.count
        }

        onPositionChanged: mouse => {
            if (!pressed || root.count === 0) return
            const slot = width / Math.max(1, root.vCount)
            if (slot <= 0) return
            const shift = Math.round((pressX - mouse.x) / slot)
            root.viewStart = Math.max(0, Math.min(pressStart + shift, root.count - root.vCount))
        }
    }

    WheelHandler {
        enabled: root.interactive && root.count > 1
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const n = root.vCount
            if (n === 0) return
            const factor = event.angleDelta.y > 0 ? 0.85 : 1 / 0.85
            const next = Math.max(Config.finance.minCandles,
                         Math.min(root.count, Math.round(n * factor)))
            if (next === n) return

            // Keep the candle under the pointer pinned while zooming.
            const frac = root.width > 0 ? Math.max(0, Math.min(1, event.x / root.width)) : 0.5
            const anchor = root.vStart + frac * n
            root.viewCount = next
            root.viewStart = Math.max(0, Math.min(Math.round(anchor - frac * next),
                                                  root.count - next))
        }
    }

    // Right-click anywhere on the chart snaps back to the full range. Declared
    // last so it sits above panArea; it only accepts the right button, so left
    // presses fall through to the drag handler below it.
    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.RightButton
        onClicked: root.resetView()
    }
}
