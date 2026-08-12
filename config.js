// Sidebar status bar font
const bar = {
    fontFamily: "Mononoki Nerd Font",
    fontSize: 22,
    height: 30
}

// SystemInfoCard profile picture. Path is relative to $HOME — drop your own
// photo there, or leave it missing to fall back to a generic icon
const systemInfo = {
    profilePic: "Pictures/ProfilePics/avatar.jpg"
}

// Unified text-size scale (Dashbord's tab 0 and onward)
const type = {
    micro: 12,   // tiny meta text (map attribution, fine print)
    label: 14,   // section headers: "HARDWARE", "WEATHER", "QUICK TOGGLES"
    sm: 16,      // secondary/meta text
    base: 18,    // default body text
    md: 20,      // emphasized text
    lg: 22,      // primary size (matches bar.fontSize)
    xl: 26,      // sub-headers, control icons
    display: 36, // large icons / big numbers
    hero: 72,    // hero-sized numbers (e.g. the weather temperature)
}

// Unified spacing/margin scale
const gap = {
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
    xxl: 28,
}

// Unified corner-radius scale (proportional/circle cases stay literal, not tokenized)
const radius = {
    xs: 3,   // thin bars
    sm: 4,   // small chips/thumbnails
    md: 6,   // small pills (tab highlight, HUD)
    lg: 8,   // toggle tiles, inset panels
    xl: 10,  // primary cards
    xxl: 12, // larger cards (Tab 2 media card)
    hero: 32,  // Outside border
    fillet: 32 // concave frame-junction fillet on popups (matches hero)
}


// Notification popup auto-dismiss timeout + history card cap
const notifications = {
    timeout: 7000,
    historyLimit: 200
}

// Screen-edge frame strip widths (see FrameReserve.qml/FrameShape.qml)
const frame = {
    thin: 8,
    thick: 64,
}

// Sidebar (left-strip status bar) module sizing
const sidebar = {
    iconSize: 26,       // app launcher / power button glyph size
    workspaceSize: 36,  // workspace chip diameter
    trayIconSize: 26,   // tray IconImage width/height
    workspaceAppIconSize: 26, // WorkspaceApps icon width/height
}

const anim = {
    slide: 600,   // dashboard open/close slide duration (ms)
    popup: 600,   // launcher open/close pop duration (ms)
    tabSlide: 600, // dashboard tab switch slide duration (ms)
}

// App launcher (command-palette) sizing
const launcher = {
    width: 820,
    maxVisibleRows: 8,
    rowHeight: 56,
    inputHeight: 56,
    iconSize: 36,
    galleryPanelWidth: 1200,
    galleryCardWidth: 340,
    galleryCardHeight: 220,
    galleryLabelHeight: 56,
    // Wallpaper picker's source folder, relative to $HOME
    wallpaperFolder: "Pictures/Wallpapers",
}

// Power menu (right-docked panel) sizing
const powerMenu = {
    width: 140,
    buttonSize: 84,
    gap: 16,
    padding: 16,
    confirmHeight: 220,
}

// Tray context menu (floating popup anchored to the clicked tray icon) sizing
const trayMenu = {
    width: 220,
    rowHeight: 32,
    padding: 8,
    gap: 2,
}

// Bluetooth menu (slides from the bar like trayMenu) sizing
const bluetoothMenu = {
    width: 280,
    rowHeight: 36,
    padding: 8,
    gap: 2,
}

// Network menu (slides from the bar at the network indicator) sizing
const networkMenu = {
    width: 320,
    rowHeight: 36,
    padding: 8,
    gap: 2,
}

// Calendar menu (slides from the bar at the clock) sizing
const calendarMenu = {
    width: 360,
    rowHeight: 30,
    cellSize: 34,
    padding: 12,
    gap: 4,
}

// Volume menu (right-docked, hover-only panel) sizing
const volumeMenu = {
    width: 160,
    sliderTrackWidth: 48,
    sliderHeight: 220,
    deviceButtonSize: 64,
    deviceRowHeight: 36,
    appRowHeight: 40,
    maxVisibleAppRows: 5,
    gap: 16,
    padding: 16,
    maxVolume: 1.5,
    snapBand: 0.06,
}

const timer = {
    interval: 1000,              // general UI tick (clock, progress displays)
    weatherRefresh: 600000,      // 10 min
    hardwareRefresh: 2000,       // Tab 0 hardware mini-chart polling
    mapSettle: 500,              // precip map: pause after pan/zoom before prefetching
    mapPrefetchStagger: 1200,    // precip map: gap between warming each radar frame
    radarFrameAdvance: 650,      // radar loop: ms per frame
    radarFrameDwell: 2200,       // radar loop: dwell on the newest frame before looping
    netRefresh: 3000,            // sidebar net up/down poll
    financeRefresh: 60000,       // Finance tab quote poll (1 min, gated on the tab being open)
}

// Finance tab - asset watchlist and price charts
const finance = {
    maxSymbols: 5,          // watchlist cap: 1 focused chart + 4 in the strip
    minCandles: 8,          // zoom floor — never show fewer candles than this
    candleMinWidth: 3,      // px/candle below which the big chart falls back to a line
    stripHeight: 150,       // height of the four secondary chart cards
    // Yahoo range/interval pairs. Both values are passed straight to
    // scripts/fetch-quotes.sh; every pair here is verified against the endpoint.
    // Intervals are chosen to keep the candle count comfortably above
    // candleMinWidth — too many candles and the chart silently degrades to a line.
    ranges: [
        { label: "1D",  range: "1d",  interval: "5m"  },  // ~79 candles
        { label: "7D",  range: "7d",  interval: "30m" },  // ~92
        { label: "6M",  range: "6mo", interval: "1d"  },  // ~124
        { label: "1Y",  range: "1y",  interval: "1d"  },  // ~251
        { label: "4Y",  range: "4y",  interval: "1wk" },  // ~211
        { label: "10Y", range: "10y", interval: "1mo" },  // ~121
    ],
    defaultRangeIdx: 3,     // 1Y
    // Watchlist shown the first time the Finance tab is opened. After that the
    // list is edited in the dashboard and persists to finance.json meaning that changing this only affects a fresh install.
    // Any Yahoo symbol works: stocks (AAPL), crypto (BTC-USD), FX (EURUSD=X), indices (^GSPC)
    defaultSymbols: ["AAPL", "GC=F", "EURUSD=X", "^GSPC", "NVDA"],
}