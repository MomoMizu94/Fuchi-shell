# Fuchi-shell

My personal desktop shell for [Hyprland](https://hyprland.org/), built with
[Quickshell](https://quickshell.org/). The colors follow the wallpaper through
pywal.

[![Watch the demo](https://github.com/user-attachments/assets/a202ed55-45ec-45c7-b7eb-e2eb312926b4)](https://www.youtube.com/watch?v=PkDNhuNavrk)

## What it includes

- A sidebar with workspaces, apps, tray icons, and desktop controls.
- A slide-out dashboard with weather, music, todos, a calendar, a stock
  watchlist, and system statistics.
- An app launcher with wallpaper selection, calculations, and shortcut search.
- Notifications with history and Do Not Disturb, plus audio and power menus.
- A CBZ/CBR library and reader with optional background downloads.

## Setup

My config expects the repository at `~/.config/quickshell`; several helpers use
that path. These startup examples use Hyprland's Lua configuration.

1. Install Quickshell, Hyprland, and the dependencies below. Make sure `qs` and
   `hyprctl` are on your `PATH`.
2. Place this repository at `~/.config/quickshell`.
3. Copy [secrets.js.example](secrets.js.example) to `secrets.js` if you don't
   already have one. This file must exist, even if you leave its defaults.
   Keep your keys and private hosts there; Git ignores it.
4. Run `qs` from your Hyprland session.
5. Open `>settings` to choose your font, wallpaper folder, and profile picture.

To start the shell automatically, add `hl.exec_cmd("qs")` to your existing
`hl.on("hyprland.start", ...)` callback. Start `awww-daemon` there too if you
use the wallpaper picker.

Bind the launcher to a key in `hyprland.lua`. This example uses Alt + P:

```lua
hl.bind("ALT + P", hl.dsp.exec_cmd("qs ipc call -- launcher toggle"))
```

### Dependencies

Use a Nerd Font for the icons. The default is `Mononoki Nerd Font`. The shell
also uses Bash and common Linux command-line tools.

| Tool or service | Used for |
| --- | --- |
| PipeWire, WirePlumber, and `wpctl` | Audio |
| NetworkManager with `nmcli`, and `ip` from iproute2 | Network status |
| BlueZ | Bluetooth |
| `curl` | Weather and market data |
| `jq` | Market-data parsing |
| pywal, providing `wal` | Wallpaper colors |
| `awww` and `awww-daemon` | Wallpapers |
| `paplay` | Notification sounds |
| `sensors` from lm_sensors | CPU temperature |
| `wl-copy` from wl-clipboard | Copying calculations |
| `hyprlock` | Screen locking |
| `systemctl` | Power actions |

Install these for the optional features you use:

| Tool | Used for |
| --- | --- |
| `nvidia-smi` | NVIDIA GPU statistics |
| `wlsunset` | Night light |
| Mullvad's `mullvad` command | VPN controls |
| Kitty and OpenSSH's `ssh` | Host terminals |
| `mpc` | Pausing MPD before suspend |
| ImageMagick's `identify` | Wallpaper dimensions |
| Python 3.10+ and Bleak | Hue Go controls |
| Python 3, `checkupdates` from pacman-contrib, and `yay` | Arch and AUR update checks |
| Python 3 and Pillow | Library indexing, covers, and CBZ reading |
| gallery-dl | Library downloads |
| libarchive with `bsdtar` and its shared library | CBR reading |
| `gio` from GLib and `notify-send` from libnotify | Library Trash and download notifications |

## Using the launcher

Type an app name, use Up and Down to select a result, and press Enter to open
it. Escape or a click outside closes the launcher. Type `>` to list commands.
Names are case-insensitive, and prefixes work, so `>key` opens the keybind list.

| Command | What it does |
| --- | --- |
| `>wallpaper` | Choose a wallpaper. Add a name to filter, such as `>wallpaper forest`. |
| `>theme` | Choose Dark or Light for the current wallpaper. |
| `>calc` | Calculate an expression. Enter copies the result. Bare expressions such as `6*7` work too. |
| `>keybinds` | Browse Hyprland shortcuts. Add words to search actions, categories, or keys. |
| `>lights` | Control a Hue Go lamp. |
| `>settings` | Open shell preferences. |
| `>Library` | Open the book library and reader. |

The keybind list shows your loaded Hyprland bindings. Scroll with the wheel,
arrows, or Page Up/Down. Enter does not execute a shortcut; replace the command
to return to app search.

## Library

Open `>Library` and choose your book and download folder under Settings > Library.
The default is `~/Library`. Search titles and artists or filter metadata.
Click a chapter, then press Enter or Read.

Arrows or clicks on either side turn pages. **D** reverses direction, **W** changes
fit, **Q/Escape** goes back, and **F/F11** toggles fullscreen reading without
controls. Reading progress and your grid position are remembered. **Auto-turn**
uses your chosen delay in seconds and stops when you leave the reader.

For downloads, install gallery-dl and paste a supported URL into Downloads.
You can cancel, retry, view logs, or discard unfinished files. Keep authentication
and cookies in your private gallery-dl config. URLs, logs, and reading state stay
outside this repository.

<details>
<summary>Folders and cover art</summary>

Folders group chapters into series; loose archives appear as individual books.
Covers use `cover.*`, artwork in `covers/`, or a thumbnail from a page.

</details>

## Optional setup

### Weather

Add your OpenWeatherMap key to `secrets.js`, using the fields in
[secrets.js.example](secrets.js.example). Set both `lat` and `lon` for a fixed
location; if either is zero, the shell uses IP-based location from `ip-api.com`.
The map uses RainViewer radar and a CARTO basemap. `cartoApiKey` is optional.

### Host shortcuts

Add SSH or web entries to `hosts` in `secrets.js`; the example file has both.
Keep each `id` unique and unchanged when renaming a host. SSH entries need Kitty
and OpenSSH. The terminal icon above the power button opens the host list.
For PADD, install it on the host and use `startupCommand: "~/padd.sh"`.

### Hue Go

For a Bluetooth-capable Hue Go, install the helper's dependency from the
repository directory:

```sh
python3 -m venv .venv-hue
.venv-hue/bin/python -m pip install -r scripts/requirements-hue.txt
```

Turn on Bluetooth, open `>lights`, choose Scan for lamps, and connect.
The shell remembers the lamp. If pairing fails, close the Hue phone app and
make the lamp discoverable.

### Package updates

Click the icon below the clock to see Arch repository and AUR updates. Checks
run at startup and hourly. Install updates yourself, then press Check now.
Failed checks retain the last known results. Change the schedule under
`updates` in `config.js`.

## Configuration

Open `>settings` for fonts, folders, animations, notifications, launcher size,
and volume limits. Changes apply and save automatically. Reset restores the
corresponding default from [config.js](config.js). You can also reload the shell
from Settings.

Edit `config.js` for other defaults, dimensions, and refresh intervals.
`scrolling.wheelStep` sets wheel travel in pixels per notch across the shell;
increase it for faster scrolling. Relative picture and wallpaper paths start
from your home directory.

`>theme` remembers your Dark or Light choice for later wallpaper changes.
GTK themes are configured separately. The Finance watchlist also saves locally;
`finance.defaultSymbols` only supplies its initial contents. Finance uses Yahoo
Finance data without an API key.

See the [customization guide](docs/customization.md) for Hyprland binding labels,
dashboard tab changes, the optional music tab, and Kitty wallpaper colors.

## Acknowledgements

[caelestia-shell](https://github.com/caelestia-dots/shell) inspired the visual
design. Fuchi-shell is an independent implementation.

[MangaReaderQS](https://github.com/sabsubGit/MangaReaderQS) informed the Library's
archive handling and metadata conventions. Its MIT notice is retained in
[licenses/MangaReaderQS.txt](licenses/MangaReaderQS.txt).
