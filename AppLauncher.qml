import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Layouts

import "config.js" as Config
import "calc.js" as Calc

PanelWindow {
    id: launcher
    signal closeRequested()

    property bool open: false
    property bool closing: false
    visible: open || closing
    onOpenChanged: {
        closing = !open
        if (open) {
            query = ""
            selectedIndex = 0
            searchInput.forceActiveFocus()
        }
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property string query: ""
    property int selectedIndex: 0

    readonly property bool commandMode: query.startsWith(">")

    // One-line-per-command registry — adding another command later is one
    // array entry + one branch in buildCommandEntries()/executeSelected(),
    // not a new framework.
    readonly property var commandDefs: [
        { name: "wallpaper", label: "Wallpaper" },
        { name: "calc", label: "Calculator" }
    ]
    property var wallpaperFiles: []   // populated once by wallpaperFolderModel below

    // Subsequence fuzzy match: query characters must appear in `text` in
    // order, not necessarily contiguously. Returns -1 for no match, otherwise
    // a score where higher = better (bonuses for word-boundary starts,
    // consecutive runs, and an early first-match position).
    function fuzzyScore(query, text) {
        if (query === "") return 0
        const q = query.toLowerCase()
        const t = text.toLowerCase()
        let qi = 0, score = 0, consecutive = 0, firstMatch = -1
        for (let ti = 0; ti < t.length && qi < q.length; ti++) {
            if (t[ti] !== q[qi]) { consecutive = 0; continue }
            if (firstMatch === -1) firstMatch = ti
            const prev = ti > 0 ? t[ti - 1] : ""
            const atBoundary = ti === 0 || /[\s\-_.]/.test(prev)
            score += 1 + consecutive * 2 + (atBoundary ? 4 : 0)
            consecutive++
            qi++
        }
        if (qi < q.length) return -1   // not all query chars found in order
        return score + Math.max(0, 8 - firstMatch)
    }

    // Best score across several optional fields (e.g. name + genericName + keywords).
    function bestFieldScore(query, fields) {
        let best = -1
        for (const f of fields) {
            if (!f) continue
            const s = fuzzyScore(query, f)
            if (s > best) best = s
        }
        return best
    }

    function parseCommand() {
        const rest = query.slice(1)
        const sp = rest.indexOf(" ")
        const word = (sp === -1 ? rest : rest.slice(0, sp)).toLowerCase()
        const filter = sp === -1 ? "" : rest.slice(sp + 1)
        return { word, filter }
    }
    function matchedCommand(word) {
        return word === "" ? null : (commandDefs.find(c => c.name.startsWith(word)) || null)
    }
    readonly property var parsedCommand: commandMode ? parseCommand() : { word: "", filter: "" }
    readonly property var activeCommand: commandMode ? matchedCommand(parsedCommand.word) : null
    readonly property bool wallpaperGridMode: !!activeCommand && activeCommand.name === "wallpaper"

    function filteredWallpapers(filter) {
        const f = filter.trim().toLowerCase()
        if (f === "") return wallpaperFiles
        const scored = []
        for (const w of wallpaperFiles) {
            const score = fuzzyScore(f, w.name)
            if (score >= 0) scored.push({ file: w, score })
        }
        scored.sort((a, b) => b.score - a.score || a.file.name.localeCompare(b.file.name))
        return scored.map(s => s.file)
    }
    function buildCommandEntries() {
        if (parsedCommand.word === "")
            return commandDefs.map(c => ({ kind: "menu", name: c.label, comment: "", command: c.name }))
        if (!activeCommand) return []
        if (activeCommand.name === "wallpaper") return filteredWallpapers(parsedCommand.filter)
        if (activeCommand.name === "calc") {
            const entry = Calc.entry(parsedCommand.filter)
            return entry ? [entry] : []
        }
        return []
    }
    readonly property var commandEntries: commandMode ? buildCommandEntries() : []

    function allApps() {
        return DesktopEntries.applications.values.filter(e => !e.noDisplay)
    }

    function filteredApps() {
        const apps = allApps()
        const q = query.trim().toLowerCase()
        if (q === "")
            return apps.slice().sort((a, b) =>
                launchCount(b.id) - launchCount(a.id) || a.name.localeCompare(b.name))
        const scored = []
        for (const e of apps) {
            const score = bestFieldScore(q, [e.name, e.genericName, ...(e.keywords || [])])
            if (score >= 0) scored.push({ entry: e, score: score + frecencyBonus(e.id) })
        }
        scored.sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name))
        return scored.map(s => s.entry)
    }

    // A bare expression typed into normal search mode (no ">" prefix) pins a
    // calc row above the app matches, so `6*7` needs no prefix at all.
    // Calc.looksLikeMath is a cheap gate; anything that slips past it — app
    // names like "7-zip" or "gimp-2.10" — fails to parse and yields null.
    function autoCalcEntry() {
        const q = query.trim()
        return Calc.looksLikeMath(q) ? Calc.entry(q) : null
    }
    function normalEntries() {
        const apps = filteredApps()
        const entry = autoCalcEntry()
        return entry ? [entry].concat(apps) : apps
    }

    readonly property var results: commandMode ? commandEntries : normalEntries()

    // Shown centred in the results area when nothing matched. "calc" needs its
    // own branch — the generic wording would read "No matching calculators".
    readonly property string emptyStateText: {
        if (!commandMode) return "No matching apps"
        if (!activeCommand) return "Unknown command “>" + parsedCommand.word + "”"
        if (activeCommand.name === "calc")
            return parsedCommand.filter.trim() === ""
                ? "Type an expression, e.g. (2+3)*4"
                : "Not a valid expression"
        return "No matching " + activeCommand.label.toLowerCase() + "s"
    }

    function scrollSelectedIntoView(idx) {
        const view = wallpaperGridMode ? wallpaperGrid : resultsList
        if (view.count > 0) view.positionViewAtIndex(idx, ListView.Contain)
    }
    onResultsChanged: {
        selectedIndex = 0
        scrollSelectedIntoView(0)
    }
    onSelectedIndexChanged: scrollSelectedIntoView(selectedIndex)

    function executeSelected() {
        if (results.length === 0) return
        const item = results[selectedIndex]
        // Kind-first: a calc row reaches here from either ">calc" or a bare
        // expression in app-search mode. DesktopEntry has no `kind`, so this
        // is safely undefined for apps.
        if (item.kind === "calc") {
            // "--" matters: without it a negative result like "-5" would be
            // read as wl-copy options. Argv-supplied text is copied verbatim
            // with no trailing newline, so nothing else is needed here.
            clipboardProc.command = ["wl-copy", "--", item.name]
            clipboardProc.startDetached()
            launcher.closeRequested()
            return
        }
        if (commandMode) {
            if (item.kind === "menu") {
                launcher.query = ">" + item.command + " "   // drill in, stay open
                return
            }
            if (item.kind === "wallpaper") {
                wallpaperProc.command = ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/set-wallpaper.sh", item.filePath]
                wallpaperProc.startDetached()
                launcher.closeRequested()
            }
            return   // unknown/unmatched command word: no-op
        }
        recordLaunch(item.id)
        item.execute()
        launcher.closeRequested()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: launcher.closeRequested()
    }

    Process { id: wallpaperProc; command: ["echo"] }
    Process { id: clipboardProc; command: ["echo"] }

    // Persistent per-app launch counts, driving frecency ranking — same
    // FileView+JsonAdapter+Quickshell.statePath pattern Dashboard.qml uses
    // for todos.json.
    FileView {
        id: launchStatsFile
        path: Quickshell.statePath("launcher-stats.json")
        watchChanges: false
        JsonAdapter {
            id: launchStatsData
            property var counts: ({})   // { [DesktopEntry.id]: launchCount }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter()
        }
    }

    function launchCount(id) {
        return launchStatsData.counts[id] || 0
    }
    function recordLaunch(id) {
        const counts = launchStatsData.counts
        counts[id] = (counts[id] || 0) + 1
        launchStatsData.counts = counts
        launchStatsFile.writeAdapter()
    }
    // Capped so frecency nudges ranking rather than overriding strong text matches.
    function frecencyBonus(id) {
        return Math.min(launchCount(id), 20) * 3
    }

    // Resolution lookup via ImageMagick's `identify` (reads just the image
    // header, not a full decode — matters since some wallpapers are 46MB+).
    // `file`'s prose output was tried first but rejected: for JPEGs it prints
    // a "density WxH" substring before the real dimensions, so a naive regex
    // would grab the wrong numbers. `identify -format "%f %wx%h"` is unambiguous.
    Process {
        id: wallpaperInfoProc
        stdout: StdioCollector { id: wallpaperInfoOut }
        onExited: {
            const map = {}
            for (const line of wallpaperInfoOut.text.split("\n")) {
                const m = line.match(/^(.*) (\d+)x(\d+)$/)
                if (m) map[m[1]] = m[2] + "×" + m[3]
            }
            launcher.wallpaperFiles = launcher.wallpaperFiles.map(w =>
                Object.assign({}, w, { resolution: map[w.name] || "" }))
        }
    }

    FolderListModel {
        id: wallpaperFolderModel
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"
        nameFilters: ["*.png", "*.jpg", "*.jpeg"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: if (status === FolderListModel.Ready) {
            const files = []
            for (let i = 0; i < count; i++)
                files.push({ kind: "wallpaper", name: get(i, "fileName"), comment: "", filePath: get(i, "filePath"), resolution: "" })
            launcher.wallpaperFiles = files
            wallpaperInfoProc.command = ["identify", "-format", "%f %wx%h\n"].concat(files.map(f => f.filePath))
            wallpaperInfoProc.running = true
        }
    }

    Item {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        width: launcher.wallpaperGridMode ? Config.launcher.galleryPanelWidth : Config.launcher.width
        Behavior on width { NumberAnimation { duration: Config.anim.popup; easing.type: Easing.OutCubic } }
        // Chrome accounting must match the anchors below exactly (top margin,
        // two dividerGap gaps around the divider, the divider itself, and the
        // bottom margin) — a mismatch here is what previously left the last
        // result row clipped by a few px.
        readonly property int outerMargin: Config.gap.xl
        readonly property int dividerGap: Config.gap.md
        height: outerMargin * 2 + dividerGap * 2 + 1 + Config.launcher.inputHeight +
            (launcher.wallpaperGridMode
                ? Config.launcher.galleryCardHeight + Config.launcher.galleryLabelHeight
                : Math.max(1, Math.min(launcher.results.length, Config.launcher.maxVisibleRows)) * Config.launcher.rowHeight)

        // Docked flush to the bottom edge via an anchor (not an animated `y`),
        // so result-count-driven height changes always grow/shrink from the
        // top with the bottom edge pinned. Only bottomMargin animates for the
        // open/close slide — when closed it pushes the panel fully below the
        // screen (-height); when open it's 0 (flush). Animating `y` and
        // `height` as two independent Behaviors previously let them drift out
        // of sync mid-transition, visibly detaching the bottom edge.
        anchors.bottom: parent.bottom
        anchors.bottomMargin: launcher.open ? 0 : -height
        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !launcher.open) launcher.closing = false
            }
        }
        Behavior on height {
            NumberAnimation { duration: Config.anim.popup; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent }

        // Concave fillets melting the panel's bottom corners into the frame's
        // inner edge (thin px above the screen edge the panel is flush with).
        CornerFillet {
            anchors.right: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.frame.thin
            solidCorner: "bottomRight"
        }
        CornerFillet {
            anchors.left: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.frame.thin
            solidCorner: "bottomLeft"
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: Config.radius.hero
            topRightRadius: Config.radius.hero
            bottomLeftRadius: 0
            bottomRightRadius: 0
            color: Colors.surface
            clip: true

            // Anchored directly (not a ColumnLayout) — a ColumnLayout's
            // Layout.fillHeight child needs its container's final height up
            // front, but panel.height is itself animated via `Behavior on
            // height` driven by resultsList.count, and Qt Quick Layouts does
            // not reliably re-stretch a fillHeight child once that animated
            // ancestor resizes after the initial layout pass — it gets stuck
            // at a sliver. Anchoring each region directly sidesteps that.
            Item {
                id: searchBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Config.gap.xl }
                height: Config.launcher.inputHeight

                RowLayout {
                    anchors.fill: parent
                    spacing: Config.gap.sm

                    Text {
                        text: "󰍉"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.sidebar.iconSize
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            text: launcher.query
                            onTextChanged: launcher.query = text

                            Keys.onDownPressed: if (launcher.results.length > 0)
                                launcher.selectedIndex = (launcher.selectedIndex + 1) % launcher.results.length
                            Keys.onUpPressed: if (launcher.results.length > 0)
                                launcher.selectedIndex = (launcher.selectedIndex - 1 + launcher.results.length) % launcher.results.length
                            Keys.onReturnPressed: launcher.executeSelected()
                            Keys.onEscapePressed: launcher.closeRequested()
                        }

                        Text {
                            anchors.fill: parent
                            visible: searchInput.text === ""
                            text: "Type \">\" for commands"
                            color: Colors.subtext
                            font: searchInput.font
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Rectangle {
                id: divider
                anchors { left: parent.left; right: parent.right; bottom: searchBar.top; margins: Config.gap.xl }
                anchors.bottomMargin: panel.dividerGap
                height: 1
                color: Colors.border
            }

            Item {
                id: resultsArea
                anchors { top: parent.top; left: parent.left; right: parent.right; bottom: divider.top; margins: Config.gap.xl }
                anchors.bottomMargin: panel.dividerGap

                ListView {
                    id: resultsList
                    anchors.fill: parent
                    clip: true
                    visible: !launcher.wallpaperGridMode
                    model: launcher.wallpaperGridMode ? [] : launcher.results
                    currentIndex: launcher.selectedIndex

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: Config.launcher.rowHeight
                        radius: Config.radius.lg
                        color: index === launcher.selectedIndex
                            ? Qt.rgba(Colors.ok.r, Colors.ok.g, Colors.ok.b, 0.2)
                            : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Config.gap.sm
                            spacing: Config.gap.md

                            // Apps carry a themed icon name; synthetic rows
                            // (the calculator) carry a Nerd Font glyph, which
                            // renders regardless of whether an icon theme is
                            // configured — themed names outside hicolor
                            // resolve to "" here and would leave a blank slot.
                            Item {
                                Layout.preferredWidth: Config.launcher.iconSize
                                Layout.preferredHeight: Config.launcher.iconSize

                                IconImage {
                                    anchors.fill: parent
                                    visible: !row.modelData.glyph
                                    source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !!row.modelData.glyph
                                    text: row.modelData.glyph || ""
                                    color: Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.sidebar.iconSize
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    color: Colors.textStrong
                                    font.bold: true
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.base
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.genericName || row.modelData.comment || ""
                                    visible: text !== ""
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcher.selectedIndex = row.index
                            onClicked: {
                                launcher.selectedIndex = row.index
                                launcher.executeSelected()
                            }
                        }
                    }
                }

                ListView {
                    id: wallpaperGrid
                    anchors.fill: parent
                    clip: true
                    visible: launcher.wallpaperGridMode
                    orientation: ListView.Horizontal
                    spacing: Config.gap.xl
                    snapMode: ListView.SnapToItem
                    model: launcher.wallpaperGridMode ? launcher.results : []
                    currentIndex: launcher.selectedIndex

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === launcher.selectedIndex
                        width: Config.launcher.galleryCardWidth
                        height: ListView.view.height

                        // No scale-on-select here: a scale transform pivots
                        // around the item's own center by default, and since
                        // `card` is taller than `thumb` alone (it also holds
                        // the label), growing it pushes `thumb`'s top edge
                        // above `card`'s own top — which wallpaperGrid's
                        // `clip: true` then cuts off. A border-only highlight
                        // avoids that class of bug entirely.
                        ClippingRectangle {
                            id: thumb
                            width: parent.width
                            height: Config.launcher.galleryCardHeight
                            radius: Config.radius.lg
                            color: Colors.card
                            border.width: card.selected ? 4 : 0
                            border.color: Colors.ok

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: Config.launcher.galleryCardWidth
                                sourceSize.height: Config.launcher.galleryCardHeight
                                source: card.modelData.filePath ? "file://" + card.modelData.filePath : ""
                            }
                        }

                        ColumnLayout {
                            anchors { top: thumb.bottom; topMargin: Config.gap.xs; left: parent.left; right: parent.right }
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: card.modelData.name
                                color: Colors.textStrong
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.base
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text !== ""
                                text: card.modelData.resolution || ""
                                color: Colors.subtext
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.type.sm
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcher.selectedIndex = card.index
                            onClicked: {
                                launcher.selectedIndex = card.index
                                launcher.executeSelected()
                            }
                        }
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: launcher.results.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: launcher.emptyStateText
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.base
                }
            }
        }
    }
}
