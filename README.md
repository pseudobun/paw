<div align="center">

<h1>paw</h1>

Keyboard-driven clicking for macOS, in the style of a sketchybar. Press a hotkey, every
clickable thing in the frontmost app gets a short label, type the label, it's clicked.
Pure Swift + AppKit, no dependencies, ~1 MB binary. Sibling of [hop](https://github.com/pseudobun/hop).

</div>

## Features

- **Hint mode** (`⌘⇧Space`): labels on every button, link, field, checkbox, tab, row… in the
  focused window, plus the menu bar and Dock when they're visible. Labels are the shortest
  prefix-free codes over the home row (`asdfghjkl;`); typing narrows them, the last key clicks.
  - last key with **⇧** = right click, **⌘** = ⌘-click (new tab), **⌥** = move the pointer there (hover)
  - the last key **twice** = double click
  - ⌫ steps back, Esc closes, any mouse click closes
  - an open menu (menu bar or context menu) is labelled instead of the window
- **Search mode** (`⌘⇧⌥Space`): an island at the top of the screen; type to fuzzy-match element
  titles, descriptions, values, placeholders and role names. Matches get labels, the best one a
  gold ring. ↵ clicks it (⇧↵ right, ⌘↵ ⌘-click), ↑↓ / ⌃N ⌃P choose, Tab switches to typing labels,
  ⌘V pastes, ⌥⌫ / ⌘⌫ delete a word / everything.
- **Scroll mode** (`⌘⇧J`): numbers the scroll areas of the focused window; **h j k l** scroll
  smoothly while held (rate-based, eased in, 120 Hz), **⇧** for speed, **d / u** half a page,
  **g / G** top / bottom, **1–9** or **Tab** switch areas. Closes after `scroll.idleTimeout` seconds.
- Web content in WebKit and Chromium via `AXUIElementsForSearchPredicate` (one call per page);
  Electron apps (`AXManualAccessibility`) and Chromium browsers (`AXEnhancedUserInterface`) are
  switched into full accessibility on first use.
- Accessibility runs off the main thread with a 0.25 s messaging timeout: a hung app costs at
  most that and never freezes paw.
- Looks like the bar: labels and the search/mode island are sketchybar islands (palette from
  `colors.lua`, GeistMono Nerd Font, radius 9 / 6, 1 px border, soft shadow). Typed keys turn gold,
  labels that stop matching fade out in 80 ms. App icons come from **sketchybar-app-font** through
  sketchybar's own `helpers/app_icons.lua`, so paw shows the same glyph as the bar.
- Multi-display: one overlay per screen, labels go to the screen their element is on.
- `~/.config/paw/config.json5`, hot-reloaded on save; `paw` CLI for skhd / sketchybar bindings.

Requires macOS 14+ on Apple Silicon.

## Install

```sh
git clone git@github.com:pseudobun/paw.git && cd paw
just local-cert   # once, on machines without an Apple Development identity
just install      # → /Applications/paw.app, CLI → /opt/homebrew/bin/paw
```

`just install` builds a release `paw.app` (`scripts/bundle.sh`) and signs it with, in order:
`$PAW_SIGN_IDENTITY`, an "Apple Development" identity, the self-signed "paw Local Signing"
certificate from `just local-cert`, or ad-hoc. Any of the first three keeps the Accessibility
grant across rebuilds; ad-hoc loses it on every build.

Fonts (the defaults; both come with the dotfiles' Brewfile / bootstrap):

```sh
brew install --cask font-geist-mono-nerd-font
curl -fsSL -o ~/Library/Fonts/sketchybar-app-font.ttf \
  https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v3.0.20/sketchybar-app-font.ttf
```

Without GeistMono paw uses SF Mono; without sketchybar-app-font islands show no app icon.

### Start at login

Either `openAtLogin: true` in the config (a login item, shown in System Settings → General →
Login Items), or `just launchd` for a LaunchAgent (`examples/dev.paw.app.plist`, restarted if it crashes).

## Permissions

paw needs **Accessibility** (System Settings → Privacy & Security → Accessibility → paw). It asks on
first launch; until it's granted the hotkeys show a red "Accessibility permission needed" island.
That one permission covers reading the UI, clicking and the key tap. No Input Monitoring,
no Screen Recording, no network.

`paw status` tells you whether the running paw is trusted. After a rebuild with ad-hoc signing,
remove paw from the list and add it again.

## CLI

The app binary is also the CLI (`/opt/homebrew/bin/paw` → `paw.app/Contents/MacOS/paw`).

| Command | |
|---|---|
| `paw hint` / `paw search` / `paw scroll` | Open (or close) a mode, like its hotkey. Starts paw.app if needed. |
| `paw reload` | Reload the config now; prints errors and unknown keys |
| `paw status` | Version, pid, Accessibility, config path |
| `paw dump [hint\|search\|scroll] [--delay=S]` | What paw finds in the frontmost app, as JSON with timings |
| `paw dump --local [--app=NAME]` | Same, collected in the terminal's process (needs Accessibility for the terminal) |
| `paw config path\|check\|show\|template` | The config file |
| `paw icon <app name>` | The sketchybar-app-font ligature for an app |
| `paw labels <n> [--charset=…]` | The labels n elements would get |
| `paw preview out.png [--fonts=DIR]` | Render labels and islands with your config |
| `paw quit` | Quit the running paw |

skhd:

```
hyper - f : paw hint
hyper - s : paw search
hyper - j : paw scroll
```

Set a mode's `hotkey` to `""` when skhd owns the binding.

## Config

`~/.config/paw/config.json5` (or `$PAW_CONFIG`). paw writes the commented default on first launch;
the same file is in [`examples/config.json5`](examples/config.json5) and `paw config template`
prints it. Every key is optional. Saving applies it at once; a broken file keeps the last good
config and shows the error in a red island.

| Key | Default | |
|---|---|---|
| `hint.hotkey` | `"cmd+shift+space"` | `cmd ctrl alt/opt shift hyper` + key; `""` = off |
| `hint.charset` | `"asdfghjkl;"` | Label keys, best first |
| `hint.menuBar` | `"auto"` | Label the app's menu bar: `auto` (unless it autohides), `true`, `false` |
| `hint.menuBarExtras` | `false` | Status items on the right |
| `hint.dock` | `"auto"` | Label the Dock: `auto` (unless it autohides), `true`, `false` |
| `hint.doubleTapMs` | `250` | Last key again within this = double click |
| `hint.restoreCursor` | `true` | Put the pointer back after a simulated click / scroll mode |
| `hint.maxElements` | `800` | Upper bound on labels |
| `hint.enhancedUI` | `true` | Set `AXEnhancedUserInterface` on Chromium browsers (can stop yabai animating their windows) |
| `search.hotkey` | `"cmd+shift+alt+space"` | |
| `search.width` | `440` | Island width |
| `search.maxResults` | `40` | Labelled matches |
| `scroll.hotkey` | `"cmd+shift+j"` | |
| `scroll.speed` | `1.6` | px per ms while held |
| `scroll.fastMultiplier` | `3` | With ⇧ |
| `scroll.rampMs` | `140` | Ease-in to full speed |
| `scroll.idleTimeout` | `5` | Seconds; `0` = stay open |
| `scroll.invert` | `false` | Flip directions |
| `appearance.font` | `"GeistMono Nerd Font"` | Falls back to SF Mono |
| `appearance.appFont` | `"sketchybar-app-font"` | |
| `appearance.fontSize` / `fontWeight` | `11` / `"bold"` | Labels |
| `appearance.labelHeight` / `labelRadius` / `labelPaddingX` | `18` / `6` / `5` | |
| `appearance.labelAnchor` | `"topLeft"` | `topLeft`, `left` or `center` of the element |
| `appearance.islandHeight` / `islandRadius` | `28` / `9` | Same as sketchybar's islands |
| `appearance.islandTop` | `46` | Island distance from the screen top (below a 40 pt bar) |
| `appearance.islandFontSize` / `appIconSize` | `12` / `14` | |
| `appearance.borderWidth` / `shadow` | `1` / `true` | |
| `appearance.fadeMs` / `unmatchedOpacity` | `80` / `0` | Labels that stop matching |
| `appearance.appIsland` | `true` | Island with app icon, mode and count while a mode is open |
| `appearance.colors.*` | sketchybar palette | `island islandHi border fg muted dim accent wave good bad`; `0xAARRGGBB`, `"#RRGGBB"` or `"#RRGGBBAA"` |
| `icons.map` | `"~/.config/sketchybar/helpers/app_icons.lua"` | sketchybar's icon map; built-in copy when missing |
| `icons.overrides` | `{}` | `{ "App Name": ":glyph:" }` |
| `excludedApps` | `[]` | Bundle ids or names where paw does nothing |
| `openAtLogin` | `false` | |
| `axTimeout` | `0.25` | Seconds to wait for a slow app |

Colours map to the bar: `island` fill, `islandHi` selected fill, `accent` (gold) for typed keys,
app icons and the selection, `wave` for scroll area numbers, `bad` for "no match" and errors.

## Development

```sh
just build      # debug build
just test       # unit tests: labels, coordinates, fuzzy match, scroll physics, config, icon map
just preview    # build/preview.png: labels and islands rendered with your config
just icons      # refresh the built-in icon map from sketchybar's app_icons.lua
just log        # paw's log; every activation logs labels, nodes and ms
```

`Sources/PawCore` is the pure logic (no AppKit, unit tested), `Sources/paw` the app:
`AX/` (traversal, clicking), `Input/` (key tap), `UI/` (overlay, islands), `Modes/`, `CLI/`.
Manual checks on a real desktop: [TESTING.md](TESTING.md).
