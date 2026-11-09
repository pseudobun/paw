<div align="center">

<h1>paw</h1>

yabai stack indicators for macOS, in the style of sketchybar. Like
[stackline](https://github.com/AdamWagner/stackline) without Hammerspoon: every yabai stack
gets a small island next to its window with one app icon per window, the focused one in gold.
Pure Swift + AppKit, no dependencies, ~1 MB. Sibling of [hop](https://github.com/pseudobun/hop).

</div>

## Features

- One vertical island per stack on every visible space and display, placed like stackline:
  outside the window on the side nearer the screen edge (`indicator.side` overrides it)
- Icons are **sketchybar-app-font** glyphs, looked up through sketchybar's own
  `helpers/app_icons.lua`, so they match the bar; the window on top of the stack gets the
  `island_hi` cell like the selected space in sketchybar, the focused window's icon is gold
- Click an icon to focus that window, scroll over the island to move through the stack,
  hover for an island with the app and window title
- Stacks without focus fade to `indicator.unfocusedOpacity`; indicators stay on their space
- Updates from yabai signals that paw adds on launch (label `paw_*`) and removes on quit,
  plus a slow poll as a safety net; bursts (dragging a window) collapse into one query
- No permissions: everything comes from the yabai CLI
- `~/.config/paw/config.json5`, hot-reloaded; same palette as sketchybar, olympus-dashboard and hop

Requires macOS 14+ on Apple Silicon and [yabai](https://github.com/koekeishiya/yabai) (stacks:
`yabai -m window --stack …`).

## Install

```sh
git clone git@github.com:pseudobun/paw.git && cd paw
just install      # → /Applications/paw.app, CLI → /opt/homebrew/bin/paw, starts paw
```

Turn off stackline first (comment out `require("stackline")` in `~/.hammerspoon/init.lua` and
reload Hammerspoon), or both draw indicators.

Fonts (defaults; both come with the dotfiles' Brewfile / bootstrap):

```sh
brew install --cask font-geist-mono-nerd-font
curl -fsSL -o ~/Library/Fonts/sketchybar-app-font.ttf \
  https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v3.0.20/sketchybar-app-font.ttf
```

Without sketchybar-app-font the cells show the app's initial.

`just install` signs with `$PAW_SIGN_IDENTITY`, an "Apple Development" identity, the
self-signed "paw Local Signing" certificate (`just local-cert`), or ad-hoc, in that order.

### Start at login

`openAtLogin: true` in the config (a login item), or `just launchd` for a LaunchAgent
(`examples/dev.paw.app.plist`, restarted if it crashes).

## CLI

The app binary is also the CLI (`/opt/homebrew/bin/paw` → `paw.app/Contents/MacOS/paw`).

| Command | |
|---|---|
| `paw refresh` | Redraw now; what the yabai signals run. Silent when paw isn't running |
| `paw hide` / `paw show` | Hide all indicators / bring them back |
| `paw stacks [--json]` | The stacks on visible spaces, as paw groups them (queries yabai itself) |
| `paw status` | Version, stacks on screen, signals, icon font, last error |
| `paw signals list\|add\|remove` | paw's yabai signals |
| `paw reload` | Reload the config now; prints errors and unknown keys |
| `paw config path\|check\|show\|template` | The config file |
| `paw icon <app>` | The sketchybar-app-font ligature for an app |
| `paw preview out.png [--fonts=DIR]` | Render two stacks with your config |
| `paw quit` | Quit (removes the signals) |

## Config

`~/.config/paw/config.json5` (or `$PAW_CONFIG`). paw writes the commented default on first
launch; the same file is [`examples/config.json5`](examples/config.json5). Every key is optional;
a broken file keeps the last good config (`paw reload` prints the error).

| Key | Default | |
|---|---|---|
| `yabai.path` | `"/opt/homebrew/bin/yabai"` | |
| `yabai.signals` | `true` | Add `paw_*` signals that run `paw refresh` |
| `yabai.pollSeconds` | `5` | Extra refresh interval; `0` = signals only |
| `yabai.fuzz` | `30` | Frames within this many points are one stack |
| `indicator.side` | `"auto"` | `auto` (stackline's rule), `left`, `right`, `insideLeft`, `insideRight` |
| `indicator.offsetX` / `offsetY` | `4` / `2` | Distance from the window's edge / top |
| `indicator.width` / `cellHeight` / `gap` / `padding` | `28` / `22` / `2` / `3` | Island geometry |
| `indicator.titles` | `"hover"` | `hover` or `never` |
| `indicator.clickToFocus` / `scrollToCycle` | `true` / `true` | |
| `indicator.unfocusedOpacity` | `0.6` | Stacks without focus |
| `indicator.fadeMs` | `150` | |
| `appearance.font` / `fontSize` | `"GeistMono Nerd Font"` / `12` | Titles; SF Mono fallback |
| `appearance.appFont` / `appIconSize` | `"sketchybar-app-font"` / `14` | |
| `appearance.radius` / `cellRadius` | `9` / `7` | sketchybar island / selected space |
| `appearance.borderWidth` / `shadow` | `1` / `true` | |
| `appearance.colors.*` | sketchybar palette | `island islandHi border fg muted dim accent wave good bad`; `0xAARRGGBB`, `"#RRGGBB"` or `"#RRGGBBAA"` |
| `icons.map` | `"~/.config/sketchybar/helpers/app_icons.lua"` | Built-in copy when missing |
| `icons.overrides` | `{}` | `{ "App Name": ":glyph:" }` |
| `excludedApps` | `[]` | App names left out of stacks |
| `openAtLogin` | `false` | |

Icon colours: focused window `accent`, top of an unfocused stack `fg`, the rest `muted`
(`dim` when the stack isn't focused).

## Development

```sh
just build      # debug build
just test       # unit tests: yabai JSON, stack grouping, placement, coordinates, config, icon map
just preview    # build/preview.png
just icons      # refresh the built-in icon map from sketchybar's app_icons.lua
just log        # paw's log
```

`Sources/PawCore` is pure logic (unit tested); `Sources/paw` is the app: `Stacks/` (yabai,
panels, controller), `UI/` (islands), `CLI/`. Manual checks: [TESTING.md](TESTING.md).
