# Customizing Fuchi-shell

These changes are optional. For installation and everyday controls, see the
[README](../README.md). Run shell commands below from `~/.config/quickshell`.

## Hyprland binding labels

`>keybinds` reads your loaded bindings with `hyprctl -j binds`. To give them
readable categories and action names, add this helper before your bindings
in `hyprland.lua`. That file lives outside this repository.

```lua
local function bindInfo(category, label, mod, flags)
    flags = flags or {}
    flags.description = table.concat({ "qsbind", category, mod or "", label }, "|")
    return flags
end
```

Pass its result as the options argument to `hl.bind`:

```lua
local mainMod = "ALT"

hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("qs ipc call -- launcher toggle"),
    bindInfo("Apps and shell", "Open launcher", mainMod))

hl.bind("XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume -l 1.3 @DEFAULT_AUDIO_SINK@ 5%+"),
    bindInfo("Media and brightness", "Increase volume", nil,
        { locked = true, repeating = true }))
```

Use your main modifier for shortcuts that should display as `Mod + key`.
Use `nil` for literal modifiers, such as Super, or keys without modifiers.
The optional `flags` argument preserves settings such as `locked` and
`repeating`. Reload Hyprland after changing bindings or labels.

New categories work without shell changes. Bindings without these descriptions
appear under Other; Lua actions without a description appear as unlabelled.

For grouped workspace ranges, use the category `Workspaces` and labels
`Switch to workspace N` or `Move window to workspace N`, with the number key
matching `N`. Missing numbers and different flags split the range. Searching
for `workspace 4` shows the individual matching bindings.

Search accepts both `Mod` and its physical modifier name. Words can match
different fields, so `window shift` finds window shortcuts that include Shift.

## Changing dashboard tabs

The tab list and content are in [Dashboard.qml](../Dashboard.qml). To replace
Finance with the included music tab:

1. In the tab-bar `Repeater`, replace the Finance entry with
   `{ icon: "󰝚", label: "Media" }`.
2. Rename the `FinanceTab` instance to `MediaTab`. Keep its dimensions,
   `dashboard` property, position, and animation.

If you reorder tabs, update their `x` expressions and the `activeTab` checks
that control refresh timers:

| Tab | Default index | Files with refresh checks |
| --- | --- | --- |
| Dashboard | `0` | [Dashboard.qml](../Dashboard.qml), [WeatherCard.qml](../Widgets/WeatherCard.qml) |
| Finance | `2` | [Dashboard.qml](../Dashboard.qml) |
| Performance | `3` | [Dashboard.qml](../Dashboard.qml) |

Calendar and Media have no refresh checks tied to their index. Replacing a tab
leaves its data-fetching code in `Dashboard.qml`; disable or remove that code
if you no longer want those requests.

## Wallpaper colors in Kitty

Install the supplied pywal template:

```sh
install -Dm644 templates/colors-kitty.conf ~/.config/wal/templates/colors-kitty.conf
```

Add this after any other theme includes in `kitty.conf`:

```conf
include ~/.cache/wal/colors-kitty.conf
```

The template covers text, background, selection, and tab colors. Apply a
wallpaper or use `>theme` to generate the colors. The wallpaper script reloads
running Kitty instances. Programs that draw their own RGB colors may need a
separate light theme.

## Wallpaper script

[scripts/set-wallpaper.sh](../scripts/set-wallpaper.sh) sets the wallpaper with
`awww` and generates the pywal palette. Edit it if you use another wallpaper
setter. [Colors.qml](../Colors.qml) reads `~/.cache/wal/colors.json`.

To recolor the current wallpaper without changing it:

```sh
bash scripts/set-wallpaper.sh --theme light
```

Use `--theme dark` to switch back. The choice persists across wallpaper changes;
the initial mode is Dark.
