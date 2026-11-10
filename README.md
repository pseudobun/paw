<div align="center">

<h1>paw</h1>

A tiling window manager for macOS with stack indicators, in the style of sketchybar.
bsp and stack layouts, virtual workspaces, workspace presets, key bindings and a CLI in one
app: no yabai, no skhd, no Hammerspoon, no SIP changes. Pure Swift + AppKit.

</div>

## Features

- **Layouts** per workspace: `bsp` (binary splits, wide tiles split side by side), `stack`
  (every window in one stack), `float`. Gaps, padding and optional room for a status bar
  (`layout.barTop`)
- **Stacks**: any tile can hold several windows. `stack <dir>` puts the focused window on the
  stack that way (merging stacks), `unstack` takes it out into its own tile, `unstack all` splits
  the whole stack; `focus stack.next|prev` goes through it, `swap stack.next|prev` reorders it
- **Moving**: `focus`, `swap`, `warp` in four directions (at the screen edge they go to the next
  display), `resize`, `balance`, `rotate`, `toggle float|zoom|split`, `grid`; dragging a tiled
  window onto another tile swaps them
- **Mouse follows focus** (and optional focus follows mouse)
- **Virtual workspaces** (like AeroSpace): `layout.workspaces` exist from the start,
  `workspace new|close|next|prev|last`, `move-to <n> [--follow]`. A hidden workspace's windows
  wait in a screen corner, so switching is instant and needs no Mission Control or SIP. ⌘Tab to a
  window on a hidden workspace switches to it
- **Presets**: `workspaces` in the config says which apps share which tile on which workspace;
  new windows of those apps land there, `arrange` puts everything back, `initiate` opens the apps
  and arranges every workspace in one go
- **Setups** per display arrangement (laptop only, home, work…): paw picks the one matching the
  connected displays by itself, pins each workspace to its display and numbers them display by
  display like yabai (`workspace new` on a display numbers it after that display's others).
  `paw initiate <setup>` (or the menu bar icon, or hop's "Set Workspace") forces one
- **Settings window** (menu bar icon → Settings…, or `paw settings`) for every key; it writes the
  same commented JSON5 file, so people and agents can keep editing the file too
- **Animations** for window moves: duration, curve (`easeOutCubic`, `spring`, `easeOutBack`…),
  and how sizes change
- **Stack indicators**: a vertical island next to each stack with one app icon per window, each
  in the app's own colour (picked from its app icon); click focuses, scroll cycles, hover shows
  the title
- **Modes**: `hyper+r` turns on resize mode (arrows or hjkl grow, with shift shrink, `esc`
  leaves) with an island at the top of the screen; define your own key modes in `modes`
- **Rules**: float or ignore apps and windows by name/title, send apps to workspaces
- **Key bindings** in the config (left/right modifiers like `ralt` work, `hyper` = ⌘⌃⌥⇧), and
  the same commands on the CLI: `paw focus west`, `paw workspace 3`
- **Hooks** for status bars: `workspaceChanged`, `windowFocused`, `windowsChanged`, `modeChanged`, `displaysChanged`, plus
  `paw query --json` ([sketchybar example](examples/sketchybar/paw_spaces.lua))

## Requirements

- macOS 14+ on Apple Silicon
- Xcode or the Command Line Tools (Swift 6), [`just`](https://github.com/casey/just)
- The **Accessibility** permission
- One native Space per display (paw's workspaces replace Spaces); in System Settings → Desktop &
  Dock, turn off "Automatically rearrange Spaces based on most recent use"
- Optional: [sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) in
  `~/Library/Fonts` for app icons in the indicators (without it they show the app's initial), and
  a Nerd Font such as `brew install --cask font-geist-mono-nerd-font` for their text
- Optional: something that turns Caps Lock into a **hyper key** (⌘⌃⌥⇧), e.g.
  [Karabiner-Elements](https://karabiner-elements.pqrs.org) or [Hyperkey](https://hyperkey.app),
  since several default bindings use `hyper`. Rebind them if you don't have one

## Install

```sh
git clone https://github.com/pseudobun/paw.git && cd paw
just local-cert   # once: a self-signed certificate, so Accessibility survives rebuilds
just install      # → /Applications/paw.app, CLI → /opt/homebrew/bin/paw, then starts paw
```

Then System Settings → Privacy & Security → Accessibility → enable paw. paw waits for the grant
and starts managing windows right after. `paw status` should show `trusted: yes` and
`bindings: ok`.

If you have an Apple Development certificate, `just install` signs with it instead of the
self-signed one (or set `PAW_SIGN_IDENTITY`). Without either it signs ad hoc, and macOS asks for
Accessibility again after every rebuild.

Stop other window managers and hotkey daemons first so they don't fight over windows, e.g.
`yabai --stop-service; skhd --stop-service`, and quit AeroSpace, Amethyst, Rectangle and the like.

Quitting paw (`paw quit`) brings every hidden window back on screen. After a crash, start paw
again (it remembers which workspace each window was on) or run `paw recover`.

Uninstall: `just uninstall`.

### Start at login

`openAtLogin: true` in the config, or `just launchd` (a LaunchAgent that restarts paw after a
crash).

## Configure

On first launch paw writes `~/.config/paw/config.json5` (or `$PAW_CONFIG`) with every default and
a comment for each key; the same file is [`examples/config.json5`](examples/config.json5). Saving
applies it at once. A broken file keeps the last good config, and `paw config check` prints the
problem. Every key is optional: delete one to get its default.

A typical setup: presets for the apps you always use, a status bar, and a key to set it all up:

```json5
{
  layout: {
    workspaces: 7,
    barTop: 41, // with a 40 pt sketchybar
  },

  // Which apps go where. Apps in one tile stack, in this order (the first one on top).
  workspaces: {
    "1": { layout: "stack", tiles: [ { apps: ["Safari"] } ] },
    "2": { layout: "bsp", tiles: [ { apps: ["Ghostty"] }, { apps: ["Zed"], size: 1.5 } ] },
    "3": { layout: "stack", tiles: [ { apps: ["Discord", "Spotify"] } ] },
    "6": { layout: "stack", tiles: [ { apps: ["Mail", "Calendar"] } ] },
    "9": { tiles: [ { apps: ["Slack"] } ], display: "secondary" },
  },

  // Per display arrangement; the first whose displays match replaces `workspaces` above.
  setups: {
    home: {
      displays: ["builtin", "DELL", "Gigabyte"], // "builtin", "external" or part of a display's name
      focus: "9",
      workspaces: {
        "1": { display: "builtin" },
        "8": { display: "DELL", layout: "stack", tiles: [ { apps: ["Discord", "Spotify"] } ] },
        "9": { display: "Gigabyte", layout: "bsp", tiles: [ { apps: ["Safari"], size: 2 }, { apps: ["Zed"] } ] },
      },
    },
  },

  // `paw initiate`: opens these apps (default: every app named in the presets), waits for their
  // windows and arranges every workspace, then shows `focus`.
  initiate: { apps: [], focus: "1", timeout: 15 },

  hooks: {
    workspaceChanged: "sketchybar --trigger paw_workspace_change",
    windowsChanged: "sketchybar --trigger paw_windows_change",
  },

  rules: [
    { app: "/^(System Settings|Calculator|Raycast)$/", float: true },
    { app: "Brave Browser", unlessTitle: "Brave", float: true }, // extension popups float
    { app: "Telegram", workspace: "5" },
  ],
}
```

Setting `bindings` or `rules` replaces the default list, so start from the ones in
`examples/config.json5` and change what you need.

| Section | Keys |
|---|---|
| `layout` | `default` (`stack`), `gap` (10), `padding {top bottom left right}` (2/2/24/24, widened on the sides to fit indicators), `barTop` (0), `barBottom` (0), `workspaces` (10), `unassignedWorkspace` ("": windows of apps no preset places stay put; or a workspace) |
| `focus` | `mouseFollowsFocus` (true), `focusFollowsMouse` (false), `wrapStacks` (false: stack next/prev stop at the ends) |
| `animation` | `enabled` (true), `durationMs` (180), `curve` (`easeOutCubic`; also `linear easeInOutCubic easeOutQuint easeOutBack spring`), `resize` (`start` / `animate` / `end`), `maxWindows` (12) |
| `bindings` | `"key": "command"`; modifiers `cmd ctrl alt shift fn hyper meh` and `lalt/ralt lcmd/rcmd lctrl/rctrl lshift/rshift`, a key name or a keycode like `0x18` |
| `modes` | `"name": { "key": "command" }`; while `mode <name>` is on its keys come first. Default: `resize` |
| `workspaces` | `"name": { layout, axis, tiles: [{ apps: ["Discord", "Spotify"], size: 1 }, …], display: "builtin" }` |
| `setups` | `"name": { displays: ["builtin", "DELL"], focus, workspaces: { … } }` |
| `initiate` | `apps` ([] = every plain app name in the presets), `focus` (""), `timeout` (15 s) |
| `rules` | `{ app, title?, unlessTitle?, manage?, float?, workspace? }`; `app`/`title` are names or `/regex/` |
| `indicator` | `side` (`auto left right insideLeft insideRight`), `offsetX/Y`, `width`, `cellHeight`, `gap`, `padding`, `titles` (`hover`/`never`), `clickToFocus`, `scrollToCycle`, `unfocusedOpacity`, `fadeMs` |
| `appearance` | `font`, `fontSize`, `appFont`, `appIconSize`, `radius`, `cellRadius`, `borderWidth`, `shadow`, `colors {island islandHi border fg muted dim accent wave good bad}` |
| `icons` | `map` (a sketchybar `app_icons.lua`; paw has a built-in copy), `overrides` (`"App": ":glyph:"`), `brandColors` (true), `colors` (`"App": "#RRGGBB"`) |
| `hooks` | `workspaceChanged`, `windowFocused`, `windowsChanged`, `modeChanged`, `displaysChanged` (shell commands with `PAW_*` variables) |
| `openAtLogin` | |

App names are what macOS shows in the menu bar (`paw query` lists the open ones); `/regex/`
matches by pattern.

### Default bindings

| Keys | |
|---|---|
| `ctrl+←↑→↓` | focus |
| `ctrl+alt+←↑→↓` | swap |
| `ctrl+shift+←↑→↓` | stack onto the neighbour |
| `cmd+shift+ctrl+←↑→↓` | warp; a stacked window with nothing that way leaves its stack to that side |
| `hyper+←/→` | previous / next window in the stack |
| `ctrl+1…0`, `ralt+1…0` | workspace 1–10 |
| `ralt+shift+1…0` | send the window to a workspace |
| `cmd+ctrl+1…0` | send and follow |
| `ralt+a/d` | previous / next workspace |
| `hyper+n`, `hyper+d` | new / close workspace |
| `hyper+w/s/f` | layout bsp / stack / float |
| `shift+alt+wasd`, `shift+ctrl+wasd` | grow / shrink |
| `hyper+e`, `alt+r` | balance, rotate |
| `hyper+r` | resize mode: `←↑→↓`/`hjkl` grow, `shift+` shrink, `e` balance, `esc`/`return` done |
| `ctrl+alt+return` | zoom |
| `ctrl+alt+space`, `ctrl+alt+c` | float, float in the middle |
| `ctrl+shift+return` | float full size |
| `ctrl+alt+u` | unstack |
| `cmd+alt+r` | recover |

### Several displays

Each display shows one workspace. Without setups the workspaces are shared: switching shows one on
the focused display, or focuses the display that already shows it. With a setup, its presets pin
workspaces to displays (`display: "DELL"`), every bar shows only its display's workspaces, and
numbers run display by display. Plugging displays in or out switches setups and retiles
everything. `focus`/`swap` past the screen edge go to the next display, `display <dir>` and
`move-to-display` move between them.

### Status bar

`paw query --json` lists every workspace with its windows, and the hooks tell the bar when to read
it again. [`examples/sketchybar/paw_spaces.lua`](examples/sketchybar/paw_spaces.lua) is a
complete sketchybar setup.

## Commands

Bindings and the CLI take the same commands; chain several with `;`
(`paw 'workspace 3; layout bsp'`).

| Command | |
|---|---|
| `focus west\|east\|north\|south` | Focus the tile that way (next display at the edge) |
| `focus stack.next\|stack.prev\|stack.first\|stack.last` | Through the focused stack |
| `swap <dir>` | Swap places with the window that way (to the next display at the edge) |
| `swap stack.next\|stack.prev` | Move the window down / up its stack |
| `warp <dir>` | Move into that tile's place, splitting it |
| `stack <dir>` | Put the window on the stack that way |
| `unstack [all]` | Take the window (every window) out of its stack |
| `layout bsp\|stack\|float` | Layout of the focused workspace |
| `toggle float\|zoom\|split` | Float, fill the workspace, flip the split |
| `resize <dir> <points>` | Move that edge (negative shrinks) |
| `balance`, `rotate 90\|180\|270` | |
| `grid rows:cols:x:y:w:h` | Float the window into a grid cell |
| `workspace <n>\|next\|prev\|last\|new\|close` | Switch, add, close (its windows go to the previous one) |
| `move-to <n>\|next\|prev [--follow]` | Send the window to a workspace |
| `display <dir>\|next\|prev\|<n>` | Focus a display |
| `move-to-display <dir>\|<n> [--follow]` | Send the window to a display's workspace |
| `arrange [workspace\|all]` | Apply the preset(s), pulling their apps from other workspaces |
| `initiate [setup]` | Open the preset apps and arrange every workspace (also `reset`); with a setup, use that one |
| `mode <name>\|exit` | Turn a key mode on (again: off) or off |
| `retile`, `recover`, `reload` | |
| `exec <shell command>` | Run something (`exec open -a Terminal`) |

paw itself: `paw status`, `paw query [--json]`, `paw setups [--json]`, `paw settings`,
`paw hide|show` (indicators), `paw reload`, `paw config path|check|show|template|format`,
`paw icon <app>`, `paw color <app>`, `paw preview out.png`, `paw quit`.

## Development

```sh
just build | test | preview | log
```

`Sources/PawCore` is pure logic and unit tested: layout tree (insert, remove, swap, warp, stack,
unstack, resize, rotate, presets), geometry and neighbours, commands, key specs, easing, config.
`Sources/paw`: `WM/` (accessibility, tracking, animator, bindings, workspaces), `Stacks/` and `UI/`
(indicators), `CLI/`. `just examples` regenerates `examples/config.json5` from the built-in
template. Manual checks: [TESTING.md](TESTING.md).
