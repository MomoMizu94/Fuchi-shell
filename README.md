# Fuchi-shell

My personal desktop shell for [Hyprland](https://hyprland.org/), built with
[Quickshell](https://quickshell.org/). It has a sidebar, an app launcher, a
slide-out dashboard, notifications, and menus for audio, networking, and power.
The colors follow the wallpaper through pywal.

[![Watch the demo](https://github.com/user-attachments/assets/a202ed55-45ec-45c7-b7eb-e2eb312926b4)](https://www.youtube.com/watch?v=PkDNhuNavrk)

Click the image to watch the full demo on YouTube.

## What it includes

The sidebar shows workspaces, running apps, the current layout, tray icons,
connection status, volume, and a clock. The dashboard opens from the top edge
and has four tabs:

- Dashboard, with weather, system information, quick toggles, music controls,
  todos, and notification history.
- Calendar, with a month view.
- Finance, with a watchlist of up to five symbols and price charts.
- Performance, with CPU, GPU, memory, and disk statistics.

A full-size music tab is also included. See [Changing dashboard tabs](#changing-dashboard-tabs)
to enable it.

The launcher searches installed apps, evaluates calculations, changes the
wallpaper, and displays Hyprland shortcuts. Notifications have a history list
and a Do Not Disturb toggle. The volume menu has separate controls for apps,
and the power menu provides lock, suspend, logout, restart, and shutdown.

## Setup

This config assumes it lives at `~/.config/quickshell`. Several commands use
that path to find the helper scripts.

1. Install Quickshell, Hyprland, and the tools listed below. The `qs` and
   `hyprctl` commands need to be on your `PATH`.
2. Place this repository at `~/.config/quickshell`.
3. Copy `secrets.js.example` to `secrets.js`. The file must exist because the
   weather components import it. Add your OpenWeatherMap key to enable weather.
4. Set your wallpaper folder and profile picture in [config.js](config.js).
5. Run `qs` from your Hyprland session.

To start the shell with Hyprland, add `hl.exec_cmd("qs")` to your existing
`hl.on("hyprland.start", ...)` callback. Start the `awww-daemon` there as well
if you use the supplied wallpaper script.

The launcher can be opened with `qs ipc call launcher toggle`. For example,
this Lua binding uses Alt + P:

```lua
hl.bind("ALT + P", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
```

### Dependencies

Use a Nerd Font for the icons. The default is `Mononoki Nerd Font`, which can
be changed in `config.js`. The shell also uses Bash, common Linux command-line
tools, and the following services and utilities:

| Tool or service | Used for |
| --- | --- |
| PipeWire and WirePlumber, including `wpctl` | Audio controls and muting before suspend |
| NetworkManager, including `nmcli`, and `ip` from iproute2 | Network status and Wi-Fi information |
| BlueZ | Bluetooth controls through Quickshell |
| `curl` | Weather, location, radar, and market-data requests |
| `jq` | Processing market-data responses |
| pywal, providing `wal` | Generating the wallpaper palette |
| `awww` and its daemon | Setting the wallpaper |
| `paplay` | Notification sounds |
| `sensors` from lm_sensors | CPU temperature |
| `wl-copy` from wl-clipboard | Copying calculator results |
| `hyprlock` | The power menu's lock action |
| `systemctl` | Suspend, restart, and shutdown |

These tools support optional parts of the shell:

| Tool | Used for |
| --- | --- |
| `nvidia-smi` | NVIDIA GPU statistics |
| `wlsunset` | The night-light toggle |
| Mullvad's `mullvad` command | VPN controls, hidden when the command is absent |
| `mpc` | Pausing MPD before suspend |
| ImageMagick's `identify` | Wallpaper dimensions in the picker |

### Weather and maps

Edit `secrets.js` with your own values:

```js
const owmApiKey = "YOUR-OPENWEATHERMAP-KEY"
const cartoApiKey = ""
const lat = 0
const lon = 0
```

The weather code requests current conditions and forecasts from
[OpenWeatherMap](https://openweathermap.org/api). Set both coordinates to use a
fixed location. If either coordinate is zero, the shell requests a location
from `ip-api.com` instead.

The weather map uses RainViewer radar over a CARTO basemap. `cartoApiKey` is
optional and is passed to the basemap requests when supplied.

`secrets.js` is ignored by Git. Keep API keys out of commits.

## Using the launcher

Type an app name to search. Matching letters do not have to be adjacent, and
frequently launched apps receive a ranking boost. Use Up and Down to choose a
result, then press Enter. Escape or a click outside closes the launcher.

Type `>` to see the available commands. Command names are case-insensitive,
and prefixes work too, so `>key` opens the keybind reference.

| Input | What happens |
| --- | --- |
| `>wallpaper` | Shows wallpapers inside the launcher. Choose one and press Enter to apply it. |
| `>wallpaper forest` | Filters wallpapers by name. |
| `>calc (2+3)*4` | Shows a calculation. Enter copies the result. |
| `6*7` | Shows a calculation above matching apps without a command prefix. |
| `>keybinds` | Shows the grouped Hyprland shortcuts inside the launcher. |
| `>keybinds window` | Filters shortcuts by action, category, or keys. |

The wallpaper picker expands the panel horizontally. The keybind view gives
it more vertical space for the scrolling reference. Both keep the input at
the bottom and use the same panel animation.

### Keybind reference

The reference reads `hyprctl -j binds` when you enter keybind mode. It shows the
loaded Hyprland configuration, including changes picked up by a config reload.
Typing a filter searches the bindings already in memory.

Use the mouse wheel, Up and Down, or Page Up and Page Down to scroll. The
input keeps keyboard focus, so you can keep typing. Enter does not execute
shortcuts. Home and End move the text cursor. Delete or replace the command
to return to app search or another launcher mode.

The header shows the main modifier, such as `Mod = Alt`. Shortcuts that use
that modifier are written as `Mod + P`; literal Super bindings still say
`Super`. You can search using either `Mod` or the physical modifier name.
Search words can match different fields, so `window shift` finds window
shortcuts that include Shift.

Repeated workspace bindings are grouped into ranges. Searching for
`workspace 4` filters the individual bindings before grouping, so the result
shows workspace 4 specifically.

#### Describing bindings in Hyprland

The Lua config is separate from this repository. To get readable categories
and action labels on another machine, add this helper before your bindings in
`hyprland.lua`:

```lua
local function bindInfo(category, label, mod, flags)
    flags = flags or {}
    flags.description = table.concat({ "qsbind", category, mod or "", label }, "|")
    return flags
end
```

Use it as the options argument of a binding. Pass your main modifier for
shortcuts that use it, or `nil` for literal modifiers. Existing flags go in
the last argument:

```lua
local mainMod = "ALT"

hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("qs ipc call launcher toggle"),
    bindInfo("Apps and shell", "Open launcher", mainMod))

hl.bind("XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume -l 1.3 @DEFAULT_AUDIO_SINK@ 5%+"),
    bindInfo("Media and brightness", "Increase volume", nil,
        { locked = true, repeating = true }))
```

These descriptions carry the category, modifier, and action label through
Hyprland's bind list. Changing `mainMod` updates both the shortcuts and the
header after Hyprland reloads. Update the label when you change an action.
New categories are supported. Bindings without these descriptions appear
under Other; Lua actions without a description appear as unlabelled.

Workspace ranges use the Workspaces category and the labels
`Switch to workspace N` or `Move window to workspace N`, where N matches the
number key. Missing keys split the range, and different flags remain separate.

## Configuration

[config.js](config.js) contains the font, spacing, text sizes, panel dimensions,
animation durations, and refresh intervals. The `keybinds.width` and
`keybinds.height` values control the expanded launcher size in keybind mode.

The profile picture and wallpaper folder are relative to your home directory:

```js
systemInfo.profilePic     // Pictures/ProfilePics/avatar.jpg
launcher.wallpaperFolder  // Pictures/Wallpapers
```

A missing profile picture falls back to a generic icon. The wallpaper picker
lists PNG and JPEG files in the configured folder.

[Colors.qml](Colors.qml) watches `~/.cache/wal/colors.json` and updates the shell
when the palette changes. [scripts/set-wallpaper.sh](scripts/set-wallpaper.sh)
sets the image with `awww`, runs `wal`, and reloads Hyprland. Edit that script
if you use a different wallpaper setter.

### Finance and saved state

The Finance tab reads Yahoo Finance's chart endpoint through
[scripts/fetch-quotes.sh](scripts/fetch-quotes.sh). The script makes requests
without an API key or account. If requests fail, check its response and your
connection before changing the UI.

`finance.defaultSymbols` sets the initial watchlist. Changes made in the
Finance tab are saved locally to `finance.json`, so editing that default does
not replace an existing watchlist.

The shell uses `Quickshell.statePath()` for the watchlist, todos, and launcher
usage counts. With the default XDG state directory, these files live under
`~/.local/state/quickshell/by-shell/<shell-id>/`.

## Changing dashboard tabs

The active tabs are defined in [Dashboard.qml](Dashboard.qml). To replace
Finance with the included music tab:

1. In the tab-bar `Repeater`, replace the Finance entry with
   `{ icon: "󰝚", label: "Media" }`.
2. In the content area, rename `FinanceTab {` to `MediaTab {`. Keep its size,
   position, `dashboard` property, and animation.

If you change tab positions, also update each component's `x` expression and
any checks of `activeTab` that control refresh timers:

| Tab | Current index | Files with refresh checks |
| --- | --- | --- |
| Dashboard | `0` | `Dashboard.qml` and `Widgets/WeatherCard.qml` |
| Finance | `2` | `Dashboard.qml` |
| Performance | `3` | `Dashboard.qml` |

Calendar and Media do not have refresh checks tied to their index. Replacing
a tab does not remove its data-fetching code from `Dashboard.qml`; remove or
disable the corresponding timer if you no longer want those requests.

## Files

| File or folder | Contents |
| --- | --- |
| `shell.qml` | Shell components, IPC handlers, notification server, and open states |
| `Bar.qml`, `Bar/` | Sidebar widgets and their menus |
| `Dashboard.qml`, `Tabs/`, `Widgets/` | Dashboard data, tab views, and widgets |
| `AppLauncher.qml` | App search, command modes, and the shared launcher panel |
| `Keybinds.qml` | The launcher's keybind view and Hyprland data loading |
| `keybinds.js` | Shortcut formatting, filtering, and workspace grouping |
| `calc.js` | The calculator's expression parser |
| `PowerMenu.qml`, `VolumeMenu.qml` | Power actions and audio controls |
| `NotificationPopup.qml` | Incoming notification popups |
| `CalendarGrid.qml`, `Events.qml` | Shared calendar grid and event helpers |
| `Colors.qml`, `config.js` | Theme colors and visual settings |
| `FrameShape.qml`, `FrameReserve.qml`, `CornerFillet.qml` | Screen frame, reserved space, and panel corners |
| `qmldir` | Local QML component registrations |
| `scripts/` | Wallpaper, system statistics, and market-data helpers |
| `assets/` | Images and animations used by widgets |
| `tests/` | Keybind formatter tests |

## Development and tests

You do not need Node.js or the tests to use Fuchi-shell. Quickshell runs the
JavaScript helpers itself.

The `tests/` folder is for people changing the code. It checks that changes
have not broken shortcut formatting or filtering. To run these checks,
install Node.js and run this command from the repository directory:

```sh
node tests/keybinds.test.cjs
```

The tests cover modifier aliases, filtering, workspace ranges, category order,
and fallback labels. They do not check how the QML renders. After changing the
launcher UI, also check app search, wallpaper mode, calculator mode, and
keybind scrolling in a running Hyprland session.

## Acknowledgements

[caelestia-shell](https://github.com/caelestia-dots/shell) inspired the visual
design. Fuchi-shell is an independent implementation.
