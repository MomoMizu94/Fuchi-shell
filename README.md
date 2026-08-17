# Fuchi-shell


My personal desktop shell for [Hyprland](https://hyprland.org/), built with [Quickshell](https://quickshell.outfoxxed.me/). It replaces a traditional bar/notification-daemon/launcher stack with a single QML shell: a status bar, a slide-out dashboard with widgets, an app launcher, notification popups + history and a power menu — all themed live from [pywal](https://github.com/dylanaraps/pywal).

## Demo

[![Demo](https://github.com/user-attachments/assets/a202ed55-45ec-45c7-b7eb-e2eb312926b4)](https://www.youtube.com/watch?v=PkDNhuNavrk)

*Click for a full YT video*

## Features

- **Bar** — workspaces (Hyprland), running-app indicators, system tray, network/Bluetooth/volume indicators, clock
- **Dashboard** — slide-out panel with tabs:
  - Overview: greeting, weather, quick toggles, hardware mini-chart, system info, notification history
  - Calendar
  - Finance (up to 5 watched assets — candlestick chart with pan/zoom for the focused one, line charts for the rest)
  - Performance (CPU/GPU/RAM/disk/network monitor)

  A fifth **Media** tab (full-size MPRIS player) ships with the config but isn't in the tab bar.
  See [Swapping tabs](#swapping-tabs) to put it back.
- **App launcher** — fuzzy-matched app search, a built-in calculator, and a wallpaper-picker command mode
- **Notifications** — popups + a persistent history list, with sound and Do Not Disturb
- **Volume menu** — per-app volume mixer via PipeWire
- **Power menu**
- **Live theming** — colors are pulled from `~/.cache/wal/colors.json` and update without restarting the shell

## Dependencies

### Required

- [Quickshell](https://quickshell.outfoxxed.me/) (`quickshell-git` on the AUR or `quickshell` via pacman) — the shell runtime itself
- [Hyprland](https://hyprland.org/) — workspaces widget uses `Quickshell.Hyprland`/`hyprctl`
- A [Nerd Font](https://www.nerdfonts.com/) — defaults to `Mononoki Nerd Font` (see `config.js`), used for all icon glyphs
- `bash`, `awk`, `curl` — used by the scripts in [scripts/](scripts/) and inline `Process` calls for stats/weather
- [`wpctl`](https://pipewire.org/) (PipeWire/WirePlumber) — volume menu and mute-on-suspend
- [`nmcli`](https://networkmanager.dev/) (NetworkManager) — network menu
- [`pywal`](https://github.com/dylanaraps/pywal) (`wal`) — palette generation from the wallpaper
- A wallpaper setter compatible with the `awww img` invocation in [scripts/set-wallpaper.sh](scripts/set-wallpaper.sh)
- `paplay` (PulseAudio/PipeWire utils) — notification sound
- `sensors` (lm_sensors) — CPU temperature in the performance tab
- [`wl-clipboard`](https://github.com/bugaevc/wl-clipboard) (`wl-copy`) — copying calculator results from the app launcher
- [`jq`](https://jqlang.github.io/jq/) — trims the market-data responses in [scripts/fetch-quotes.sh](scripts/fetch-quotes.sh)

### Optional

- `nvidia-smi` — GPU stats (skipped gracefully if absent/non-NVIDIA)
- `wlsunset` — night-light toggle in the dashboard
- [`mullvad`](https://mullvad.net/) (Mullvad VPN CLI) — VPN toggle and kill switch in the network
  menu; the section is hidden if the binary is absent
- `mpc` (MPD client) — paused on suspend, only relevant if you run MPD
- [ImageMagick](https://imagemagick.org/) (`identify`) — reads wallpaper dimensions for the
  picker's resolution labels

### Market data 

The Finance tab reads Yahoo Finance's chart endpoint via [scripts/fetch-quotes.sh](scripts/fetch-quotes.sh).
No API key or account is needed, and one URL shape covers stocks, crypto, FX and indices. If the tab ever goes blank 
that script is the only place to fix — if you ever want to switch the provider for the data, you just need to fix the script.

The starting watchlist is `finance.defaultSymbols` in [config.js](config.js). It's only a starting
point — when you add or remove assets in the dashboard, your list is saved to `finance.json` under
`~/.local/state/quickshell/`. So what's in `config.js` is just what a fresh install opens with, 
not a record of what you actually track. Your real watchlist stays locally on your machine.

### API keys

Weather uses the [OpenWeatherMap](https://openweathermap.org/api) API and IP-based geolocation via `ip-api.com`. Copy [secrets.js.example](secrets.js.example) to `secrets.js` and fill in your API key:

```js
const owmApiKey = "YOUR-KEY-HERE"

// Optional fixed location; leave as 0 to auto-detect via IP
const lat = 0
const lon = 0
```

`secrets.js` is gitignored and must not be committed. This is the only file holding anything
private — the Finance tab needs no key at all.

## Installation

1. Install Quickshell and the dependencies above. Prefer your package manager — it should put the `qs`
   command on your `PATH`, which the bar's menus call.
2. Clone this repo to `~/.config/quickshell`.
3. Copy `secrets.js.example` to `secrets.js` and add your OpenWeatherMap API key.
4. Point `systemInfo.profilePic` and `launcher.wallpaperFolder` in [config.js](config.js) at your
   own paths — see [Configuration](#configuration) below.
5. Launch with `qs` (or however you start Quickshell from your Hyprland config).

## Structure

```
shell.qml              Entry point — IPC handlers, notification server, global state
Bar.qml, Bar/          Status bar and its indicators/menus
Dashboard.qml          Slide-out dashboard container + shared state/polling
Tabs/                  Dashboard tab contents
Widgets/               Reusable dashboard cards (incl. PriceChart.qml, the finance renderer)
AppLauncher.qml        App launcher / command palette
PowerMenu.qml          Power menu
VolumeMenu.qml         Per-app volume mixer
NotificationPopup.qml  On-screen notification popups
CalendarGrid.qml       Month grid shared by the calendar tab and the bar's calendar popup
Events.qml             Singleton: calendar events + shared date helpers
Colors.qml             Singleton: pywal-backed color palette
FrameShape.qml         Draws the screen-edge frame; also holds the hover hot-zones
FrameReserve.qml       Reserves the left strip so tiled windows avoid it
CornerFillet.qml       Concave corner piece where popups meet the frame
config.js              Central sizing/spacing/timing tokens + path settings
calc.js                Expression parser behind the launcher's calculator
qmldir                 Component registry — every .qml must be listed here to be importable
assets/                GIFs used by the music widgets
scripts/               Helper scripts (perf, net speed, wallpaper, market data)
```

## Configuration

Most sizing, spacing, colors, and timing values are centralized in [config.js](config.js) — tweak values there before touching individual `.qml` files.

Two settings point at your own files and are worth setting first, since the defaults won't match
your machine. Both paths are relative to `$HOME`:

```js
systemInfo.profilePic     // default: "Pictures/ProfilePics/avatar.jpg"
launcher.wallpaperFolder  // default: "Pictures/Wallpapers"
```

The profile picture is shown in the Overview tab's system-info card; if nothing is found at that
path it falls back to a generic icon. The wallpaper folder is what the launcher's `>wallpaper` picker lists
- point it to your own wallpaper folder.

## Swapping tabs

The dashboard has four tabs, and a spare `MediaTab` that isn't wired in. Swapping one for another
is two edits in [Dashboard.qml](Dashboard.qml) — nothing else needs to change, since every tab
takes the same properties.

For example, to replace the Finance tab with Media, change its entry in the tab-bar `Repeater`:

```js
{ icon: "󰄪", label: "Finance" }   // before
{ icon: "󰝚", label: "Media"   }   // after
```

...and rename the matching component further down, leaving everything inside it alone:

```qml
FinanceTab {                                        // before
MediaTab {                                          // after
    y: 0
    width: contentArea.width
    height: contentArea.height
    x: (2 - dashboard.activeTab) * contentArea.width
    dashboard: dashboard
    ...
}
```

That works for any tab in either direction — the two edits are always the same.

**One caveat if you *reorder* tabs** (rather than just swapping contents): three tabs only refresh
their data while visible, and that check is hardcoded to their position. If you move one, update
its number to match:

| Tab | Check | Where |
| --- | --- | --- |
| Overview | `activeTab === 0` | `Dashboard.qml` **and** `Widgets/WeatherCard.qml` (two places) |
| Finance | `activeTab === 2` | `Dashboard.qml` |
| Performance | `activeTab === 3` | `Dashboard.qml` |

Calendar and Media have no such check, so they can be moved freely.

## Acknowledgements

Visually inspired by [caelestia-shell](https://github.com/caelestia-dots/shell) — the look and
feel of that project shaped a lot of the design direction here. This is an independent
implementation rather than a fork or a port of its code.
