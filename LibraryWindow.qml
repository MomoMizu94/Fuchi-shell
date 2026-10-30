import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import "config.js" as Config
import "settings.js" as Paths
import "library.js" as Logic

FloatingWindow {
    id: window
    title: "Fuchi-shell Library"
    visible: false
    implicitWidth: Config.library.width
    implicitHeight: Config.library.height
    minimumSize: Qt.size(620, 480)
    color: Colors.surface
    property alias controller: library
    property string view: "library"
    readonly property bool pageOnly: fullscreen && view === "reader"
    property string currentId: ""
    readonly property var currentBook: library.books.find(book => book.id === currentId) || null
    property int chapterIndex: -1
    property string currentFile: ""
    property var pages: []
    property int page: 0
    property bool opening: false
    property bool atPreviousEnd: false
    property bool rtl: true
    property string fit: "page"
    property string sort: "recent"
    property bool autoTurning: false
    property int autoTurnSeconds: 10
    property var filters: ({})
    property bool filtersVisible: false
    property bool downloadsVisible: false
    property string trashTarget: ""
    property string trashName: ""
    property string discardJob: ""
    property string imageError: ""
    readonly property var shownBooks: Logic.filtered(library.books, search.text, filters, sort)
    readonly property int filterCount: Object.keys(filters).length
    onFiltersChanged: if (grid) grid.resetPosition()
    onSortChanged: if (grid) grid.resetPosition()
    onViewChanged: {
        if (view !== "reader") autoTurning = false
        if (view === "library" && grid) grid.restorePosition()
    }
    onPageChanged: if (autoPageTimer.running) autoPageTimer.restart()
    onImageErrorChanged: if (imageError) autoTurning = false
    onPageOnlyChanged: if (pageOnly) Qt.callLater(function() {
        if (window.pageOnly) reader.forceActiveFocus()
    })

    function showLibrary() {
        visible = true
        minimized = false
        Qt.callLater(function() {
            const nativeWindow = window.contentItem.Window.window
            if (nativeWindow) {
                nativeWindow.raise()
                nativeWindow.requestActivate()
            }
        })
    }
    function hideLibrary() {
        savePosition()
        visible = false
    }
    onClosed: hideLibrary()
    onVisibleChanged: {
        if (!visible) autoTurning = false
        if (visible && view === "library") grid.restorePosition()
    }

    function openBook(book) {
        if (view === "library") {
            // Capture the actual position even if a model refresh still has a
            // deferred restore queued when the user opens a book.
            grid.savedY = grid.contentY
            grid.savedIndex = grid.currentIndex
        }
        currentId = book.id
        chapterIndex = -1
        if (book.chapters.length === 1) openChapter(0)
        else {
            view = "chapters"
            Qt.callLater(function() { chapters.forceActiveFocus() })
        }
    }
    function openChapter(index, atEnd) {
        if (!currentBook || index < 0 || index >= currentBook.chapters.length) return
        savePosition()
        chapterIndex = index
        currentFile = currentBook.chapters[index].file
        pages = []
        page = 0
        atPreviousEnd = !!atEnd
        opening = true
        imageError = ""
        view = "reader"
        library.request({op: "open", file: currentFile})
        Qt.callLater(function() {
            if (window.visible && window.view === "reader") reader.forceActiveFocus()
        })
    }
    function savePosition(done) {
        if (view === "reader" && pages.length && currentFile)
            library.request({op: "progress", file: currentFile, page: page,
                done: done === undefined ? null : done})
    }
    function goTo(index) {
        if (opening || !pages.length) return
        page = Math.max(0, Math.min(pages.length - 1, index))
        savePosition()
    }
    function nextPage() {
        if (opening || !pages.length) return
        if (page < pages.length - 1) goTo(page + 1)
        else {
            savePosition(true)
            if (currentBook && chapterIndex + 1 < currentBook.chapters.length) openChapter(chapterIndex + 1)
            else back()
        }
    }
    function previousPage() {
        if (opening || !pages.length) return
        if (page > 0) goTo(page - 1)
        else if (chapterIndex > 0) openChapter(chapterIndex - 1, true)
    }
    function back() {
        if (opening) return
        if (view === "reader") {
            savePosition()
            pages = []
            currentFile = ""
            view = currentBook && currentBook.chapters.length > 1 ? "chapters" : "library"
            library.refresh()
        } else if (view === "chapters") {
            view = "library"
            currentId = ""
        } else hideLibrary()
        if (view === "chapters") chapters.forceActiveFocus()
        else if (view === "library") grid.forceActiveFocus()
    }
    function mark(files, done) {
        library.request({op: "mark", files: files, done: done})
    }
    function askTrash(path, name) {
        trashTarget = path
        trashName = name
        trashDialog.open()
    }
    function setFit(value) {
        fit = value
        library.request({op: "setting", key: "fit", value: value})
    }
    function setDirection(value) {
        rtl = value
        library.request({op: "setting", key: "rtl", value: value})
    }
    function setAutoTurnSeconds(value) {
        autoTurnSeconds = Math.max(1, Math.min(3600, Math.round(value)))
        library.request({op: "setting", key: "autoTurnSeconds", value: autoTurnSeconds})
    }

    Timer {
        id: autoPageTimer
        interval: window.autoTurnSeconds * 1000
        repeat: true
        running: window.autoTurning && window.visible && !window.minimized
            && window.view === "reader" && !window.opening && window.pages.length > 0
            && pageImage.status === Image.Ready && !window.imageError && !autoTurnDelay.activeFocus
        onTriggered: window.nextPage()
    }

    LibraryService {
        id: library
        active: window.visible
        onOpened: chapter => {
            if (chapter.file !== window.currentFile || window.view !== "reader") return
            window.pages = chapter.pages
            window.page = window.atPreviousEnd ? chapter.pages.length - 1
                : Math.max(0, Math.min(chapter.page, chapter.pages.length - 1))
            window.opening = false
            window.savePosition()
        }
        onFailed: (operation, message) => {
            if (operation === "open") {
                window.opening = false
                window.autoTurning = false
            }
        }
        onBooksChanged: {
            const book = books.find(entry => entry.id === window.currentId)
            const index = book && window.currentFile
                ? book.chapters.findIndex(chapter => chapter.file === window.currentFile) : -1
            if (window.currentId && (!book || (window.currentFile && index < 0))) {
                window.pages = []
                window.currentFile = ""
                window.currentId = ""
                window.view = "library"
            } else if (index >= 0) {
                // Imports can insert chapters before the one currently open.
                window.chapterIndex = index
            }
        }
        onReaderSettingsChanged: {
            window.rtl = readerSettings.rtl === undefined ? true : readerSettings.rtl
            window.fit = readerSettings.fit || "page"
            window.sort = readerSettings.sort || "recent"
            window.autoTurnSeconds = readerSettings.autoTurnSeconds === undefined ? 10 : readerSettings.autoTurnSeconds
        }
        onFolderChanged: {
            window.pages = []
            window.currentFile = ""
            window.currentId = ""
            window.chapterIndex = -1
            window.opening = false
            window.view = "library"
            window.filters = ({})
            grid.resetPosition()
        }
    }

    Shortcut { sequences: [StandardKey.Close]; enabled: window.visible; onActivated: window.hideLibrary() }
    Shortcut {
        sequence: "F11"
        enabled: window.visible
        autoRepeat: false
        onActivated: window.fullscreen = !window.fullscreen
    }

    Pane {
        id: content
        objectName: "libraryContent"
        anchors.fill: parent
        padding: window.pageOnly ? 0 : Config.gap.xl
        font.family: Settings.fontFamily
        font.pixelSize: Config.type.sm
        palette.window: Colors.surface
        palette.windowText: Colors.text
        palette.base: Colors.inset
        palette.text: Colors.text
        palette.placeholderText: Colors.subtext
        palette.button: Colors.card
        palette.buttonText: Colors.text
        palette.highlight: Colors.accent
        palette.highlightedText: Colors.contrastText
        palette.mid: Colors.border
        palette.dark: Colors.border
        palette.light: Colors.card
        background: Rectangle { color: Colors.surface }

        ColumnLayout {
            anchors.fill: parent
            spacing: Config.gap.md

            RowLayout {
                objectName: "libraryHeader"
                visible: !window.pageOnly
                Layout.fillWidth: true
                spacing: Config.gap.md
                SettingsButton {
                    objectName: "libraryBack"
                    visible: window.view !== "library"
                    text: "Back"
                    enabled: !window.opening
                    onClicked: window.back()
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Config.gap.xs
                    Label {
                        Layout.fillWidth: true
                        text: window.view === "library" ? "Library"
                            : window.currentBook ? window.currentBook.name : "Library"
                        textFormat: Text.PlainText
                        font.pixelSize: Config.type.xl
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: window.view !== "reader"
                        text: window.view === "library"
                            ? library.books.length + (library.books.length === 1 ? " book" : " books")
                            : window.currentBook ? window.currentBook.chapters.length + " chapters" : ""
                        color: Colors.subtext
                        font.pixelSize: Config.type.label
                    }
                }
                SettingsButton {
                    objectName: "libraryDownloads"
                    text: library.downloading ? "Downloading…" : "Downloads"
                    onClicked: window.downloadsVisible = !window.downloadsVisible
                }
                SettingsButton {
                    text: window.fullscreen ? "Windowed" : "Fullscreen"
                    onClicked: window.fullscreen = !window.fullscreen
                }
            }

            Label {
                Layout.fillWidth: true
                visible: !window.pageOnly && library.error !== ""
                text: library.error
                textFormat: Text.PlainText
                color: Colors.error
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
            }
            Label {
                Layout.fillWidth: true
                visible: library.warnings.length > 0 && window.view !== "reader"
                text: library.warnings.length + " archive or cover problem(s). " + library.warnings.slice(0, 3).join("\n")
                textFormat: Text.PlainText
                color: Colors.warn
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: !window.pageOnly && library.ready && !library.writable && library.books.length > 0
                text: "This folder is read-only. Reading is available; downloads and Trash require write access."
                color: Colors.warn
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: window.view === "library"
                TextField {
                    id: search
                    objectName: "librarySearch"
                    Layout.fillWidth: true
                    placeholderText: "Search titles or artists"
                    selectByMouse: true
                    Accessible.name: "Search library"
                    onTextChanged: grid.resetPosition()
                    Keys.onDownPressed: grid.forceActiveFocus()
                    Keys.onEscapePressed: if (text) text = ""; else window.back()
                }
                ComboBox {
                    objectName: "librarySort"
                    model: ["Last read", "Alphabetical"]
                    currentIndex: window.sort === "name" ? 1 : 0
                    Accessible.name: "Library order"
                    onActivated: index => {
                        window.sort = index ? "name" : "recent"
                        library.request({op: "setting", key: "sort", value: window.sort})
                    }
                }
                SettingsButton {
                    text: window.filterCount ? "Filters (" + window.filterCount + ")" : "Filters"
                    onClicked: window.filtersVisible = !window.filtersVisible
                }
                SettingsButton {
                    id: refreshButton
                    objectName: "libraryRefresh"
                    implicitWidth: refreshText.width + leftPadding + rightPadding
                    TextMetrics { id: refreshText; font: refreshButton.font; text: "Loading…" }
                    text: library.loading ? "Loading…" : "Refresh"
                    enabled: !library.loading
                    onClicked: library.refresh()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Config.gap.lg
                visible: window.view === "library"
                Rectangle {
                    Layout.preferredWidth: Math.min(290, content.width * 0.4)
                    Layout.fillHeight: true
                    visible: window.filtersVisible
                    radius: Config.radius.xl
                    color: Colors.card
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Config.gap.md
                        spacing: Config.gap.sm
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Filters"; font.bold: true; Layout.fillWidth: true }
                            SettingsButton { text: "Clear"; enabled: window.filterCount > 0; onClicked: window.filters = ({}) }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Select to include, again to exclude, again to clear."
                            wrapMode: Text.Wrap
                            font.pixelSize: Config.type.label
                            color: Colors.subtext
                        }
                        ComboBox {
                            id: facetField
                            Layout.fillWidth: true
                            model: ["Tags", "Languages", "Artists", "Characters", "Parodies", "Censorship"]
                            property var fields: ["tags", "languages", "artists", "characters", "parodies", "censorship"]
                            Accessible.name: "Metadata filter type"
                        }
                        TextField {
                            id: facetSearch
                            Layout.fillWidth: true
                            placeholderText: "Find a filter"
                            Accessible.name: "Find metadata filter"
                        }
                        ListView {
                            id: facets
                            ScrollWheel { view: facets }
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Config.gap.xs
                            model: Logic.facets(library.books, facetField.fields[facetField.currentIndex], facetSearch.text)
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Button {
                                id: facet
                                required property var modelData
                                width: ListView.view.width
                                property string key: facetField.fields[facetField.currentIndex] + ":" + modelData.value
                                property int mode: window.filters[key] || 0
                                text: (mode === 1 ? "+ " : mode === -1 ? "− " : "") + modelData.value + " (" + modelData.count + ")"
                                font.family: Settings.fontFamily
                                font.pixelSize: Config.type.label
                                Accessible.name: modelData.value + (mode === 1 ? ", included" : mode === -1 ? ", excluded" : "")
                                onClicked: window.filters = Logic.toggle(window.filters, key)
                                contentItem: Text {
                                    text: facet.text
                                    textFormat: Text.PlainText
                                    font: facet.font
                                    color: facet.mode ? Colors.contrastText : Colors.text
                                    wrapMode: Text.Wrap
                                }
                                background: Rectangle {
                                    radius: Config.radius.md
                                    color: facet.mode === -1 ? Colors.error : facet.mode === 1
                                        ? Colors.accent : facet.hovered ? Colors.inset : "transparent"
                                    border.width: facet.visualFocus ? 2 : 0
                                    border.color: Colors.text
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: facets.count === 0
                            text: "No matching metadata. Archives without metadata remain in the unfiltered library."
                            color: Colors.subtext
                            wrapMode: Text.Wrap
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    GridView {
                        id: grid
                        ScrollWheel { view: grid }
                        objectName: "libraryGrid"
                        property real savedY: 0
                        property int savedIndex: 0
                        property var positionedModel: null
                        property bool restoringPosition: false
                        function rememberPosition() {
                            // A model reset changes contentY before modelChanged.
                            // Record movement only while the displayed model is stable.
                            if (window.visible && window.view === "library" && !restoringPosition
                                    && positionedModel === window.shownBooks) {
                                savedY = contentY
                                savedIndex = currentIndex
                            }
                        }
                        function restorePosition() {
                            restoringPosition = true
                            Qt.callLater(finishRestore)
                        }
                        function finishRestore() {
                            if (window.visible && window.view === "library") {
                                forceLayout()
                                currentIndex = count > 0 ? Math.max(0, Math.min(savedIndex, count - 1)) : -1
                                const maximumY = originY + Math.max(0, contentHeight - height)
                                contentY = Math.max(originY, Math.min(savedY, maximumY))
                                savedY = contentY
                                savedIndex = currentIndex
                            }
                            positionedModel = window.shownBooks
                            restoringPosition = false
                        }
                        function resetPosition() {
                            savedY = 0
                            savedIndex = 0
                            restorePosition()
                        }
                        onContentYChanged: rememberPosition()
                        onCurrentIndexChanged: rememberPosition()
                        onModelChanged: restorePosition()
                        anchors.fill: parent
                        clip: true
                        cellWidth: width / Math.max(1, Math.floor(width / 332))
                        cellHeight: 504
                        model: window.shownBooks
                        keyNavigationEnabled: true
                        ScrollBar.vertical: ScrollBar {}
                        Keys.onReturnPressed: if (currentIndex >= 0 && currentIndex < count) window.openBook(model[currentIndex])
                        Keys.onEnterPressed: if (currentIndex >= 0 && currentIndex < count) window.openBook(model[currentIndex])
                        Keys.onEscapePressed: window.back()
                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            width: grid.cellWidth
                            height: grid.cellHeight
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Config.gap.sm
                                color: Colors.card
                                radius: Config.radius.xl
                                border.width: grid.activeFocus && grid.currentIndex === card.index ? 2 : 0
                                border.color: Colors.accent
                            }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Config.gap.lg
                                spacing: Config.gap.sm
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: Colors.inset
                                    radius: Config.radius.sm
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: Paths.fileUrl(card.modelData.cover, Quickshell.env("HOME"))
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        sourceSize.width: 360
                                        sourceSize.height: 520
                                    }
                                    Label {
                                        anchors.centerIn: parent
                                        visible: !card.modelData.cover
                                        text: "No cover"
                                        color: Colors.subtext
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    text: card.modelData.name
                                    textFormat: Text.PlainText
                                    font.pixelSize: Config.type.sm
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                ProgressBar {
                                    id: bookProgress
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 4
                                    padding: 0
                                    value: card.modelData.done / card.modelData.chapters.length
                                    Accessible.name: "Completed chapters"
                                    background: Rectangle {
                                        color: Colors.inset
                                        radius: Config.radius.xs
                                    }
                                    contentItem: Item {
                                        Rectangle {
                                            width: parent.width * bookProgress.visualPosition
                                            height: parent.height
                                            radius: Config.radius.xs
                                            color: Colors.accent
                                        }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: card.modelData.done + " / " + card.modelData.chapters.length + " read"
                                    color: Colors.subtext
                                    font.pixelSize: Config.type.label
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    grid.currentIndex = card.index
                                    grid.forceActiveFocus()
                                    if (mouse.button === Qt.RightButton) {
                                        bookMenu.book = card.modelData
                                        bookMenu.popup()
                                    } else window.openBook(card.modelData)
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name
                            Accessible.onPressAction: window.openBook(modelData)
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 32, 480)
                        visible: grid.count === 0
                        spacing: Config.gap.md
                        Label {
                            Layout.fillWidth: true
                            text: library.loading ? "Reading your library…"
                                : library.books.length ? "No matching books" : "Your library is empty"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Config.type.lg
                        }
                        Label {
                            Layout.fillWidth: true
                            text: library.books.length ? "Change the search or clear the filters."
                                : "Choose your library folder in Settings, add CBZ or CBR files, or open Downloads and paste a URL."
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: Colors.subtext
                        }
                        SettingsButton {
                            Layout.alignment: Qt.AlignHCenter
                            visible: window.filterCount > 0
                            text: "Clear filters"
                            onClicked: window.filters = ({})
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: window.view === "chapters"
                spacing: Config.gap.md
                RowLayout {
                    Layout.fillWidth: true
                    SettingsButton {
                        objectName: "libraryContinue"
                        text: "Continue reading"
                        enabled: !!window.currentBook && !library.busy
                        onClicked: window.openChapter(window.currentBook.resume)
                    }
                    Item { Layout.fillWidth: true }
                    SettingsButton {
                        text: "Series actions"
                        enabled: !!window.currentBook
                        onClicked: {
                            bookMenu.book = window.currentBook
                            bookMenu.popup()
                        }
                    }
                }
                ListView {
                    id: chapters
                    ScrollWheel { view: chapters }
                    objectName: "libraryChapters"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Config.gap.sm
                    model: window.currentBook ? window.currentBook.chapters : []
                    ScrollBar.vertical: ScrollBar {}
                    Keys.onReturnPressed: window.openChapter(currentIndex)
                    Keys.onEscapePressed: window.back()
                    delegate: Rectangle {
                        id: chapterRow
                        objectName: "libraryChapterRow" + index
                        required property var modelData
                        required property int index
                        readonly property bool selected: chapters.currentIndex === index
                        width: ListView.view.width
                        height: 72
                        radius: Config.radius.lg
                        color: selected ? Qt.tint(Colors.card,
                            Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)) : Colors.card
                        border.width: selected ? 2 : 0
                        border.color: Colors.accent
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                chapters.currentIndex = chapterRow.index
                                chapters.forceActiveFocus()
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Config.gap.md
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: chapterRow.modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                                Label {
                                    text: chapterRow.modelData.done ? "Read" : chapterRow.modelData.read
                                        ? "Page " + (chapterRow.modelData.page + 1) + " of " + chapterRow.modelData.pages
                                        : chapterRow.modelData.pages + " pages"
                                    color: Colors.subtext
                                    font.pixelSize: Config.type.label
                                }
                            }
                            SettingsButton {
                                text: chapterRow.modelData.done ? "Mark unread" : "Mark read"
                                onClicked: window.mark([chapterRow.modelData.file], !chapterRow.modelData.done)
                            }
                            SettingsButton {
                                text: "Read"
                                enabled: !window.opening
                                onClicked: window.openChapter(chapterRow.index)
                            }
                            SettingsButton {
                                text: "Trash"
                                enabled: library.writable
                                onClicked: window.askTrash(chapterRow.modelData.file, chapterRow.modelData.name)
                            }
                        }
                    }
                }
            }

            FocusScope {
                id: readerFocus
                objectName: "libraryReader"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: window.view === "reader"
                Keys.onPressed: event => {
                    event.accepted = true
                    const forward = window.rtl ? Qt.Key_Left : Qt.Key_Right
                    const backward = window.rtl ? Qt.Key_Right : Qt.Key_Left
                    if (event.key === forward) window.nextPage()
                    else if (event.key === backward) window.previousPage()
                    else if (event.key === Qt.Key_Space || event.key === Qt.Key_PageDown) reader.scrollForward()
                    else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_PageUp) reader.scrollBackward()
                    else if (event.key === Qt.Key_Down) reader.scrollBy(0.25)
                    else if (event.key === Qt.Key_Up) reader.scrollBy(-0.25)
                    else if (event.key === Qt.Key_Home) window.goTo(0)
                    else if (event.key === Qt.Key_End) window.goTo(window.pages.length - 1)
                    else if (event.key === Qt.Key_W) window.setFit(window.fit === "page" ? "width" : "page")
                    else if (event.key === Qt.Key_D) window.setDirection(!window.rtl)
                    else if (event.key === Qt.Key_F && event.modifiers === Qt.NoModifier) {
                        if (!event.isAutoRepeat) window.fullscreen = !window.fullscreen
                    }
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) window.back()
                    else event.accepted = false
                }
                ColumnLayout {
                    anchors.fill: parent
                    spacing: Config.gap.sm
                    Item {
                        id: reader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Quantize resize changes so dragging an edge does not
                        // repeatedly decode the same page at near-identical sizes.
                        readonly property int decodeWidth: Math.max(128, Math.ceil(width * Screen.devicePixelRatio / 128) * 128)
                        readonly property int decodeHeight: Math.max(128, Math.ceil(height * Screen.devicePixelRatio / 128) * 128)
                        function scrollBy(amount) {
                            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height,
                                flick.contentY + amount * flick.height))
                        }
                        function scrollForward() {
                            if (window.fit === "width" && !flick.atYEnd) scrollBy(0.85)
                            else window.nextPage()
                        }
                        function scrollBackward() {
                            if (window.fit === "width" && !flick.atYBeginning) scrollBy(-0.85)
                            else window.previousPage()
                        }
                        function turnWheelPage(wheel) {
                            if (wheel.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
                            const delta = wheel.pixelDelta.y || wheel.angleDelta.y
                            if (delta < 0) window.nextPage()
                            else if (delta > 0) window.previousPage()
                            wheel.accepted = delta !== 0
                        }
                        Rectangle { anchors.fill: parent; color: Colors.inset; radius: window.pageOnly ? 0 : Config.radius.lg }
                        Flickable {
                            id: flick
                            objectName: "libraryPageViewport"
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: Math.max(height, pageImage.height)
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: window.fit === "width"
                            ScrollWheel {
                                id: readerWheel
                                view: flick
                                parent: readerPointer
                                enabled: window.fit === "width"
                                onUnhandledWheel: wheel => reader.turnWheelPage(wheel)
                            }
                            Image {
                                id: pageImage
                                objectName: "libraryPageImage"
                                source: window.pages.length ? Paths.fileUrl(window.pages[window.page], Quickshell.env("HOME")) : ""
                                asynchronous: true
                                fillMode: Image.Stretch
                                smooth: true
                                sourceSize.width: reader.decodeWidth
                                sourceSize.height: window.fit === "width" ? 0 : reader.decodeHeight
                                width: window.fit === "page" && implicitHeight > 0
                                    ? Math.min(flick.width, flick.height * implicitWidth / implicitHeight) : flick.width
                                height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : flick.height
                                x: (flick.width - width) / 2
                                y: window.fit === "page" ? Math.max(0, (flick.height - height) / 2) : 0
                                onSourceChanged: { flick.contentY = 0; window.imageError = "" }
                                onStatusChanged: if (status === Image.Error) window.imageError = "Could not display this page image."
                            }
                            ScrollBar.vertical: ScrollBar { visible: window.fit === "width" && !window.pageOnly }
                        }
                        Image {
                            objectName: "libraryPagePreloader"
                            visible: false
                            asynchronous: true
                            fillMode: Image.Stretch
                            sourceSize.width: reader.decodeWidth
                            sourceSize.height: window.fit === "width" ? 0 : reader.decodeHeight
                            source: window.page + 1 < window.pages.length
                                ? Paths.fileUrl(window.pages[window.page + 1], Quickshell.env("HOME")) : ""
                        }
                        MouseArea {
                            id: readerPointer
                            anchors.fill: parent
                            onClicked: mouse => {
                                reader.forceActiveFocus()
                                if ((mouse.x < width / 2) === window.rtl) window.nextPage()
                                else window.previousPage()
                            }
                            onWheel: wheel => {
                                if (window.fit === "width" && readerWheel.scroll(wheel, true)) return
                                reader.turnWheelPage(wheel)
                            }
                        }
                        Label {
                            anchors.centerIn: parent
                            text: window.imageError || (window.opening ? "Opening chapter…" : window.pageOnly ? library.error : "")
                            visible: text !== ""
                            color: window.imageError ? Colors.error : Colors.text
                        }
                    }
                    RowLayout {
                        objectName: "libraryPageControls"
                        visible: !window.pageOnly
                        Layout.fillWidth: true
                        SettingsButton { text: "Previous"; enabled: !window.opening; onClicked: window.previousPage() }
                        Label {
                            Layout.fillWidth: true
                            text: window.pages.length ? "Page " + (window.page + 1) + " of " + window.pages.length : ""
                            horizontalAlignment: Text.AlignHCenter
                            color: Colors.subtext
                        }
                        SettingsButton {
                            text: window.fit === "page" ? "Fit width" : "Fit page"
                            onClicked: window.setFit(window.fit === "page" ? "width" : "page")
                        }
                        SettingsButton {
                            text: window.rtl ? "RTL" : "LTR"
                            Accessible.name: window.rtl ? "Right-to-left page turns" : "Left-to-right page turns"
                            ToolTip.visible: hovered
                            ToolTip.text: window.rtl ? "Right to left. Click to change." : "Left to right. Click to change."
                            onClicked: window.setDirection(!window.rtl)
                        }
                        SettingsButton { text: "Next"; enabled: !window.opening; onClicked: window.nextPage() }
                    }
                    RowLayout {
                        objectName: "libraryAutoTurnControls"
                        visible: !window.pageOnly
                        Layout.fillWidth: true
                        spacing: Config.gap.sm
                        Item { Layout.fillWidth: true }
                        SettingsButton {
                            objectName: "libraryAutoTurn"
                            text: window.autoTurning ? "Stop auto-turn" : "Auto-turn"
                            enabled: window.autoTurning || (!window.opening && window.pages.length > 0 && !window.imageError)
                            onClicked: {
                                window.autoTurning = !window.autoTurning
                                reader.forceActiveFocus()
                            }
                        }
                        Label { text: "Every"; color: Colors.subtext }
                        SpinBox {
                            id: autoTurnDelay
                            objectName: "libraryAutoTurnSeconds"
                            Layout.preferredWidth: 140
                            from: 1
                            to: 3600
                            value: window.autoTurnSeconds
                            editable: true
                            Accessible.name: "Seconds per page"
                            onValueModified: window.setAutoTurnSeconds(value)
                        }
                        Label { text: "seconds"; color: Colors.subtext }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            Rectangle {
                objectName: "libraryDownloadsPanel"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(310, content.height * 0.4)
                visible: window.downloadsVisible && !window.pageOnly
                radius: Config.radius.xl
                color: Colors.card
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Config.gap.md
                    spacing: Config.gap.sm
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: downloadUrl
                            objectName: "libraryDownloadUrl"
                            Layout.fillWidth: true
                            placeholderText: "Paste a series or gallery URL"
                            selectByMouse: true
                            Accessible.name: "Download URL"
                            onAccepted: downloadButton.clicked()
                        }
                        SettingsButton {
                            id: downloadButton
                            objectName: "libraryDownloadButton"
                            text: "Download"
                            enabled: library.galleryAvailable && library.writable && downloadUrl.text.trim() !== ""
                            onClicked: {
                                if (!enabled) return
                                library.request({op: "add", url: downloadUrl.text.trim()})
                                downloadUrl.text = ""
                            }
                        }
                        SettingsButton {
                            text: details.visible ? "Hide details" : "Details"
                            onClicked: details.visible = !details.visible
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: !library.galleryAvailable
                        text: "Install gallery-dl, then refresh Library to enable downloads."
                        color: Colors.warn
                        wrapMode: Text.Wrap
                    }
                    ListView {
                        id: downloads
                        ScrollWheel { view: downloads }
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Config.gap.sm
                        model: library.jobs.slice().reverse()
                        ScrollBar.vertical: ScrollBar {}
                        delegate: RowLayout {
                            id: download
                            required property var modelData
                            width: ListView.view.width
                            spacing: Config.gap.sm
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: download.modelData.url
                                    textFormat: Text.PlainText
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Config.type.label
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: download.modelData.error || download.modelData.status
                                        + (download.modelData.status === "running" ? " / " + download.modelData.files + " images received" : "")
                                    textFormat: Text.PlainText
                                    color: download.modelData.status === "failed" ? Colors.error : Colors.subtext
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Config.type.label
                                }
                            }
                            SettingsButton {
                                text: "Cancel"
                                visible: ["pending", "running"].includes(download.modelData.status)
                                onClicked: library.request({op: "cancel", job: download.modelData.id})
                            }
                            SettingsButton {
                                text: "Retry"
                                visible: ["failed", "cancelled"].includes(download.modelData.status)
                                enabled: library.writable && library.galleryAvailable
                                onClicked: library.request({op: "add", url: download.modelData.url})
                            }
                            SettingsButton {
                                text: "Discard files…"
                                objectName: "libraryDiscardFiles_" + download.modelData.id
                                visible: ["failed", "cancelled"].includes(download.modelData.status)
                                    && !download.modelData.discarded
                                onClicked: {
                                    window.discardJob = download.modelData.id
                                    discardDialog.open()
                                }
                            }
                        }
                    }
                    ScrollView {
                        id: details
                        ScrollWheel { view: details.contentItem }
                        Layout.fillWidth: true
                        Layout.preferredHeight: 100
                        visible: false
                        clip: true
                        TextArea {
                            objectName: "libraryDownloadLog"
                            text: library.log || "No download details yet."
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: Settings.fontFamily
                            font.pixelSize: Config.type.micro
                            color: Colors.text
                            background: Rectangle { color: Colors.inset; radius: Config.radius.md }
                        }
                    }
                }
            }
        }

        Menu {
            id: bookMenu
            property var book: null
            MenuItem {
                text: "Continue reading"
                onTriggered: if (bookMenu.book) {
                    window.currentId = bookMenu.book.id
                    window.openChapter(bookMenu.book.resume)
                }
            }
            MenuItem {
                text: "Mark all read"
                onTriggered: if (bookMenu.book) window.mark(bookMenu.book.chapters.map(c => c.file), true)
            }
            MenuItem {
                text: "Mark all unread"
                onTriggered: if (bookMenu.book) window.mark(bookMenu.book.chapters.map(c => c.file), false)
            }
            MenuSeparator {}
            MenuItem {
                text: "Move to Trash…"
                enabled: library.writable
                onTriggered: if (bookMenu.book) window.askTrash(bookMenu.book.id, bookMenu.book.name)
            }
        }
        Dialog {
            id: discardDialog
            objectName: "libraryDiscardDialog"
            anchors.centerIn: parent
            width: Math.max(320, Math.min(480, content.width - 32))
            implicitHeight: topPadding + bottomPadding + discardMessage.implicitHeight
                + header.implicitHeight + footer.implicitHeight + spacing * 2
            title: "Discard working files?"
            modal: true
            footer: DialogButtonBox {
                SettingsButton { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
                SettingsButton { text: "Discard files"; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
                onAccepted: discardDialog.accept()
                onRejected: discardDialog.reject()
            }
            contentItem: Item {
                implicitHeight: discardMessage.implicitHeight
                Label {
                    id: discardMessage
                    width: parent.width
                    text: "Permanently remove this download's unfinished files. Saved books and reading progress are kept. A later retry downloads the files again."
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }
            onAccepted: library.request({op: "discard", job: window.discardJob})
        }
        Dialog {
            id: trashDialog
            objectName: "libraryTrashDialog"
            anchors.centerIn: parent
            width: Math.min(480, content.width - 32)
            title: "Move to Trash?"
            modal: true
            footer: DialogButtonBox {
                SettingsButton { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
                SettingsButton { text: "Move to Trash"; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
                onAccepted: trashDialog.accept()
                onRejected: trashDialog.reject()
            }
            contentItem: Label {
                text: window.trashName + "\n\nThis moves the selected chapter or entire series folder to the desktop Trash."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            onAccepted: {
                if (window.trashTarget === window.currentId) {
                    window.currentId = ""
                    window.view = "library"
                }
                library.request({op: "trash", file: window.trashTarget})
            }
        }
    }
}
