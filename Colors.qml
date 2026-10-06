pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Basic pywal palette (~/.cache/wal/colors.json), updated live.
// Slot map: background/foreground = special; color0-7 = palette; color8-15 = bright mirrors.
// Tweak a role = change its slot on that line. Fallbacks apply only when pywal never ran.
Singleton {
    id: root

    property var wal: ({})
    readonly property bool themed: wal.special !== undefined
    function s(k, fb) { return themed ? wal.special[k] : fb }
    function c(i, fb) { return themed ? wal.colors["color" + i] : fb }

    property color bg:         s("background", "#1A1F2B")
    readonly property bool isLight: bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114 > 0.5
    property color surface:    bg
    property color card:       themed ? (isLight ? Qt.darker(bg, 1.06) : Qt.lighter(bg, 1.35)) : "#252B36"
    property color inset:      themed ? Qt.darker(bg, isLight ? 1.12 : 1.40) : "#10131a"
    property color border:     c(8, "#2A313E")
    property color text:       s("foreground", "#DDE3EA")
    property color textStrong: c(15, "#F2EDDC")
    property color subtext:    c(8, "#6B7A94")
    property color contrastText: root.bg
    property color accent:     c(3, "#D18870")
    property color accent2:    c(5, "#F2C3A7")
    property color accentAlt:  c(6, "#90BDBC")
    property color accent3:    c(4, "#5E82AD")
    property color ok:         c(2, "#A4BF8D")
    property color warn:       c(3, "#ECCC8C")
    property color error:      c(1, "#C0616A")

    FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.wal = JSON.parse(text()) } catch(e) {} }
    }
}
