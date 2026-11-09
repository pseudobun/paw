<div align="center">

<h1>paw</h1>

A tiling window manager for macOS with stack indicators, in the style of sketchybar.
bsp and stack layouts, virtual workspaces, key bindings and a CLI in one app: no yabai,
no skhd, no Hammerspoon, no SIP changes. Pure Swift + AppKit. Sibling of [hop](https://github.com/pseudobun/hop).

</div>

## Features

- **Layouts** per workspace: `bsp` (binary splits, wide tiles split side by side), `stack`
  (every window in one stack), `float`. Gaps, padding and room for sketchybar (`layout.barTop`)
- **Stacks**: any tile can hold several windows. `stack <dir>` puts the focused window on the
  stack that way (merging stacks), `unstack` takes it out into its own tile, `unstack all` splits
  the whole stack; `focus stack.next|prev` goes through it
- **Moving**: `focus`, `swap`, `warp` in four directions (at the edge they go to the next display,
  like the old `|| display --focus`), `resize`, `balance`, `rotate`, `toggle float|zoom|split`,
  `grid`; dragging a tiled window onto another tile swaps them
- **Mouse follows focus** (and optional focus follows mouse)
- **Workspaces** like AeroSpace: 1–10 from the start, `workspace new|close|next|prev|last`,
  `move-to <n> [--follow]`; one workspace per display, a hidden workspace's windows wait in a
  screen corner, so switching is instant and needs no Mission Control or SIP. ⌘Tab to a window on a
  hidden workspace switches to it
- **Presets**: `workspaces` in the config says which apps share which tile; new windows of those
  apps land there, `arrange` puts everything back
- **Animations** for window moves: duration, curve (`easeOutCubic`, `spring`, `easeOutBack`…),
  and how sizes change, all in the config
- **Stack indicators**: a vertical island next to each stack with one sketchybar-app-font icon per
  window (same glyphs as the bar); click focuses, scroll cycles, hover shows the title
- **Rules**: float or ignore apps and windows by name/title, send apps to workspaces
- **Key bindings** in the config (left/right modifiers like `ralt` work), the same commands on
  the CLI: `paw focus west`, `paw workspace 3`; defaults are the old skhdrc
- **Hooks** for sketchybar: `hooks.workspaceChanged` runs with `$PAW_WORKSPACE`; `paw query --json`

Requires macOS 14+ on Apple Silicon and the **Accessibility** permission. Use one native Space per
display (paw's workspaces replace them).

## Install

```sh
git clone git@github.com:pseudobun/paw.git && cd paw
just local-cert   # once: a stable signature, so Accessibility survives rebuilds
just install      # → /Applications/paw.app, CLI → /opt/homebrew/bin/paw
```

Then System Settings → Privacy & Security → Accessibility → paw. paw waits for the grant and
starts managing windows right after.

Before the first start, stop the old tools so they don't fight over windows:

```sh
yabai --stop-service; skhd --stop-service
# Hammerspoon: quit it (it only ran stackline)
```

Fonts: `brew install --cask font-geist-mono-nerd-font` and sketchybar-app-font in
`~/Library/Fonts` (both come with the dotfiles).

Quitting paw (`paw quit`, `pkill paw`) brings every hidden window back on screen. After a crash,
start paw again (it remembers which workspace each window was on) or run `paw recover`.

### Start at login

`openAtLogin: true` in the config, or `just launchd` (LaunchAgent, restarted after a crash).

## Commands

Bindings and the CLI take the same commands; chain several with `;`.

| Command | |
|---|---|
| `focus west\|east\|north\|south` | Focus the tile that way (next display at the edge) |
| `focus stack.next\|stack.prev\|stack.first\|stack.last` | Through the focused stack |
| `swap <dir>` | Swap places with the window that way (to the next display at the edge) |
| `warp <dir>` | Move into that tile's place, splitting it |
| `stack <dir>` | Put the window on the stack that way |
| `unstack [all]` | Take the window (every window) out of its stack |
| `layout bsp\|stack\|float` | Layout of the focused workspace |
| `toggle float\|zoom\|split` | Float, fill the workspace, flip the split |
| `resize <dir> <points>` | Move that edge (negative shrinks) |
| `balance`, `rotate 90\|180\|270` | |
| `grid rows:cols:x:y:w:h` | Float the window into a grid cell |
| `workspace <n>\|next\|prev\|last\|new\|close` | Switch, add, close (windows go to the previous one) |
| `move-to <n>\|next\|prev [--follow]` | Send the window to a workspace |
| `display <dir>\|next\|prev\|<n>` | Focus a display |
| `move-to-display <dir>\|<n> [--follow]` | Send the window to a display's workspace |
| `arrange [workspace]` | Apply the workspace's preset |
| `retile`, `recover`, `reload` | |
| `exec <shell command>` | Run something (`exec open -a Alacritty`) |

paw itself: `paw status`, `paw query [--json]`, `paw hide|show` (indicators), `paw reload`,
`paw config path|check|show|template`, `paw icon <app>`, `paw preview out.png`, `paw quit`.

## Config

`~/.config/paw/config.json5` (or `$PAW_CONFIG`), written with every default on first launch; the
same file is [`examples/config.json5`](examples/config.json5). Saving applies it at once; a broken
file keeps the last good one (`paw reload` prints the error). Every key is optional.

| Section | Keys |
|---|---|
| `layout` | `default` (`stack`), `gap` (10), `padding {top bottom left right}` (2/2/24/24), `barTop` (41), `barBottom` (0), `workspaces` (10) |
| `focus` | `mouseFollowsFocus` (true), `focusFollowsMouse` (false) |
| `animation` | `enabled` (true), `durationMs` (180), `curve` (`easeOutCubic`; also `linear easeInOutCubic easeOutQuint easeOutBack spring`), `resize` (`start` / `animate` / `end`), `maxWindows` (12) |
| `bindings` | `"key": "command"`; keys are `cmd ctrl alt shift fn hyper meh`, `lalt/ralt lcmd/rcmd lctrl/rctrl lshift/rshift`, key names or `0x18`. Setting it replaces the defaults (your skhdrc) |
| `workspaces` | `"1": { layout, axis, tiles: [{ apps: ["Discord", "Spotify"], size: 1 }, …], display: "main" }` |
| `rules` | `{ app, title?, unlessTitle?, manage?, float?, workspace? }`; `app`/`title` are names or `/regex/`. Defaults are the old yabairc rules |
| `indicator` | `side` (`auto left right insideLeft insideRight`), `offsetX/Y`, `width`, `cellHeight`, `gap`, `padding`, `titles` (`hover`/`never`), `clickToFocus`, `scrollToCycle`, `unfocusedOpacity`, `fadeMs` |
| `appearance` | `font`, `fontSize`, `appFont`, `appIconSize`, `radius`, `cellRadius`, `borderWidth`, `shadow`, `colors {island islandHi border fg muted dim accent wave good bad}` |
| `icons` | `map` (sketchybar's `app_icons.lua`), `overrides` |
| `hooks` | `workspaceChanged`, `windowFocused` (shell, with `PAW_*` variables) |
| `openAtLogin` | |

A preset example:

```json5
workspaces: {
  "1": { layout: "bsp", tiles: [ { apps: ["Discord", "Spotify"] }, { apps: ["Ghostty"], size: 1.5 } ] },
  "2": { layout: "stack", tiles: [ { apps: ["Safari", "Zed"] } ] },
  "9": { tiles: [ { apps: ["Slack"] } ], display: "secondary" },
},
```

## Development

```sh
just build | test | preview | log
```

`Sources/PawCore` is pure logic and unit tested: layout tree (insert, remove, swap, warp, stack,
unstack, resize, rotate, presets), geometry and neighbours, commands, key specs, easing, config.
`Sources/paw`: `WM/` (accessibility, tracking, animator, bindings, workspaces), `Stacks/` and `UI/`
(indicators), `CLI/`. Manual checks: [TESTING.md](TESTING.md).
