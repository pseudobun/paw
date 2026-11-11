# Testing paw by hand

`just test` covers the layout logic; a window manager also needs a real desktop. Keep `just log` open.

## Switch over

- [ ] Stop other window managers / hotkey daemons (`yabai --stop-service; skhd --stop-service`)
- [ ] One native Space per display (Mission Control)
- [ ] `just local-cert` (once), `just install`, grant Accessibility; `paw status` → `trusted: yes`,
      `bindings: ok`, `iconFont: ok`, windows counted

## Layout and stacks

- [ ] Existing windows tile on workspace 1 in stack layout (the default); indicator island beside it
- [ ] `hyper+w` → bsp; `hyper+s` → stack; `hyper+f` → float (windows stay where they are)
- [ ] In bsp: new window splits the focused one (wide → side by side, tall → top/bottom), with the gap and side padding, below `layout.barTop`
- [ ] `ctrl+arrows` focus moves; pointer jumps into the window; at the screen edge it goes to the other display
- [ ] `ctrl+alt+arrows` swap; at the edge the window goes to the other display
- [ ] `cmd+shift+ctrl+arrows` warp
- [ ] `ctrl+shift+arrows` stacks the window onto its neighbour; indicator appears with both icons
- [ ] `hyper+left/right` cycles the stack; gold icon follows
- [ ] `ctrl+alt+u` unstacks; `paw unstack all` splits the whole stack
- [ ] Click / scroll / hover on the indicator
- [ ] `shift+alt+wasd` / `shift+ctrl+wasd` resize; `hyper+e` balance; `alt+r` rotate
- [ ] `hyper+r` → RESIZE island at the top; arrows/hjkl grow, shift shrinks, `esc` leaves (island goes)
- [ ] `ctrl+alt+return` zoom; `ctrl+alt+space` float (centred, 2/3); `ctrl+alt+c` float in the middle cell; `ctrl+shift+return` floats full size
- [ ] Drag a tiled window: an accent preview follows the pointer. Middle of a tile → swap; with ⌥ → stack; outer edge of a tile → splits it on that side; on the gap between tiles → a new tile there, siblings equal; past the screen's edge → docks beside everything; on its own tile → snaps back
- [ ] Drag a tiled window onto another display → it joins that display's workspace where you dropped it
- [ ] Hover the gap between two tiles → a line fades in, cursor ↔/↕; drag it → both sides resize live, the next tile gives way once one is small; double-click → even
- [ ] Drag a tiled window's edge with the mouse → the tile resizes (neighbours follow) instead of snapping back
- [ ] bsp (`hyper+w`): open windows until they'd get smaller than 640×400 → the screen shows only the branch around the focused one; `ctrl+arrows` past the edge pans to the next ones; the overview shows the whole canvas with the on-screen part outlined
- [ ] Squeeze a window whose app has a minimum size (System Settings-like apps, Codex, T3) → after a moment it leaves, a placeholder (icon, title, "needs more room") takes its tile; click it → gold outline, `ctrl+alt+arrows` swaps it; in a bigger tile the window shows again; drag it like a window; double-click → zooms in until it fits; `paw retile` forgets the learned sizes
- [ ] Enable `focus.focusFollowsMouse`: hover a placeholder → its outline and keyboard focus move there, with the app still parked; move to a normal window → focus follows back. Disable it in Settings → hovering stops focusing, clicking still works. Drag across another placeholder or cover it with a floating window → it must not steal focus
- [ ] With focus-follows-mouse enabled, open a native file picker in Teams (or another app) and let it overlap a neighbouring app's tile. Hover the overlapping part → the picker stays in front; hover an uncovered part of the neighbouring window → focus follows normally. Repeat with `border.enabled: true`
- [ ] With focus-follows-mouse enabled, start a region capture in a screenshot tool and move the pointer across windows (and displays): selection stays active. Cancel with `esc` → normal hover focus resumes
- [ ] Focus a placeholder while another app is frontmost, then `ctrl+alt+return` → its window fills the workspace, comes in front of the other apps, and accepts typing without a click; toggle back → its placeholder stays selected. Repeat with `ctrl+alt+space` → the floating window comes forward and accepts typing
- [ ] `hyper+j` on `A | (B / C)` with B focused → B and C fill the workspace, A hides; again → B alone; `hyper+k` twice → all back; HUD shows the level; switching workspace drops the zoom
- [ ] ⌥-scroll up / ⌥-pinch out over a window zooms in towards it, animated; down / pinch in zooms out
- [ ] Overview: drag across empty stage (or ⇧-drag over windows) → those windows' branch fills the screen
- [ ] `ctrl+arrows` past the edge onto a display with an empty workspace → pointer and HUD go there
- [ ] Resizing (keys, seam, window edge) stops where a neighbour reaches its minimum; shrinking back zooms back out by itself
- [ ] `hyper+z` undoes the last swap/warp/resize/drop on the workspace, `hyper+y` redoes
- [ ] `hyper+w/s/f` again; `paw layout columns` → equal columns, new windows add a column; `paw layout master` → 62% left, the rest in rows
- [ ] Animations: smooth? Try `animation.curve: "spring"`, `durationMs: 250`, `resize: "animate"`, `enabled: false`

## A hung app

- [ ] Put TextEdit windows on workspaces 1 and 2, then `kill -STOP $(pgrep -x TextEdit)`: `hyper+w/s`, swaps, resizes, focus and workspace switches still answer at once (`just bench hung TextEdit`: every command well under 100 ms); `kill -CONT` → TextEdit's windows land where the layout says
- [ ] Hold a resize key for a few seconds, let go → resizing stops at once (no backlog keeps running)
- [ ] Scroll and type in other apps while paw lays out many windows → no stutter
- [ ] Lock the screen, `paw quit; open -a paw` (or restart over SSH), unlock → within a couple of seconds paw manages every window (`paw status` → `windows:`)

## Workspaces

- [ ] `ctrl+1…0` and `ralt+1…0` switch instantly; windows of other workspaces are out of sight (one pixel in the bottom-right corner)
- [ ] `ralt+shift+N` sends a window, `cmd+ctrl+N` sends and follows
- [ ] `ralt+a/d` prev/next; `hyper+n` new; `hyper+d` closes (windows go to the previous workspace)
- [ ] ⌘Tab to an app whose window is on another workspace → paw switches there
- [ ] Two displays: each shows its own workspace; `workspace N` for one shown on the other display just focuses it
- [ ] Close a window → focus stays on the same workspace (doesn't jump to another window of that app elsewhere)
- [ ] Minimise / ⌘H an app → its tile closes; restore → it comes back to the same tile and size
- [ ] Quit an app whose windows were tiled, open it again → same tiles
- [ ] `just install` (paw restarts) → every workspace keeps its tiles, sizes and stacks
- [ ] Switching workspaces flashes the HUD (number + app icons); `hud.workspace: false` turns it off
- [ ] `hyper+o` / `hyper+i` go back and forward through focused windows, switching workspaces; `paw find zed` goes to Zed
- [ ] `paw quit` → every window back on screen; start again → windows return to their workspaces

## Displays

- [ ] `hyper+]` / `hyper+[` (đ / š) move the focused workspace's windows one place right / left, past the last one onto the next display; `paw move-workspace 5` from 3 → Discord + Spotify now on 5, 5's windows on 3; focus follows; the bar follows
- [ ] Overview: drag card 3 onto card 5 → they trade contents
- [ ] Overview: drag a workspace card onto another display → "Move workspace N here", drop → it moves
- [ ] Unplug a display whose workspaces have windows: preset apps land on their preset workspace, the rest on `+N` (first in the bar); `paw workspace +N` goes there; moving the last one out makes `+N` disappear; empty workspaces of that display are gone

## Overview

- [ ] `border.enabled: true` (Settings → Look → Focus border) → a line around the focused window; follows focus, swaps, stacks, floating windows; around a focused placeholder too; colour/width change live
- [ ] With `border.autoRadius: true`, focus Finder, an Electron app, and a square window: each outline matches its corners. Turn matching off: all use `border.radius`. Drag/resize a floating window, switch displays, and focus a placeholder; the line follows without reshaping at screen edges. Try a terminal that changes its title rapidly: an unchanged border must not redraw

- [ ] `hyper+tab` → every display dims; rail of workspace cards, the current one large; `hyper+tab`/`esc` closes
- [ ] Arrows move the gold outline; past the left/right edge → previous/next workspace; `tab`, `1`–`9`
- [ ] Type "saf" → Safari selected (maybe on another workspace), others dimmed, cards show match counts; `esc` clears, `esc` closes
- [ ] `return` goes there; `shift+return` brings it to the current workspace
- [ ] Drag a window onto a card → it moves there (overview stays open); onto the stage → drop zones with preview
- [ ] Stack: click one of its icons → that window; double-click a card → that workspace; `+` → new workspace
- [ ] Screen Recording allowed (`overview.thumbnails: "on"`) → window pictures, hidden workspaces too
- [ ] Middle-button drag up → overview; left/right → previous/next workspace; plain middle click still pastes / opens a link in a new tab

## Events

- [ ] `paw subscribe` → a `snapshot` line, then lines as you switch, focus, open/close windows, resize; `seq` counts up
- [ ] `paw subscribe --reconnect` keeps going across `paw quit` / `open -a paw`
- [ ] sketchybar spaces update through the bridge (`pgrep -fl "paw subscribe"`), hooks for them empty

## Presets and rules

- [ ] Add a `workspaces` preset (README example), then `paw arrange 1` → apps in the right tiles and sizes
- [ ] Quit the preset apps, `paw initiate` → they open and land on their workspaces, `initiate.focus` is shown
- [ ] Quit and reopen an app from a preset → it lands in its tile
- [ ] A tile with `title` gets only matching windows; `launch` runs from `initiate` when none is open
- [ ] System Settings, Raycast, CleanShot float; a Brave extension popup floats, the main Brave window tiles
- [ ] `rules: [{ app: "Slack", workspace: "9" }]` → new Slack window opens on 9 without stealing focus

## Changing a window's minimum size

With paw running and at least one empty hidden workspace, run:

```sh
python3 scripts/test-window-minimum.py
```

This opt-in native AX test uses two temporary fixture windows on an empty workspace. A real
1000-point minimum must stay a placeholder; the driver then tells the app to lower it to 400.
Switching away and back must recover the window and native keyboard focus without a corrective
`find` or `retile`. A pending check must not reveal it on a hidden workspace; the fixture
checks its WindowServer bounds intersect no display beyond a one-point parking strip.
AppKit can clamp the vertical position, so the strip need not be only one point tall.
The script closes its fixture and restores the previous workspace and the empty workspace's
layout. Use a display narrower than 2000 points so the initial half-screen tile cannot fit,
and leave the keyboard and mouse alone during the run.

Also test Arc/Brave: after a temporary size refusal, focus the placeholder again; windows
that now fit return, while genuinely undersized tiles remain placeholders. Try closing a
window or switching workspace during the delayed size check. Check with animations both on
and off, and keep focus-follows-mouse enabled if that is your usual configuration.

While a recoverable placeholder is selected, activate an app excluded by `manage: false` and
change the hidden window's title: it may recover, but must not take focus. Also activate the
excluded app immediately after focusing a recoverable placeholder; the delayed check must
leave focus with that app.

- [ ] With adjacent displays forcing left-corner parking, retry a placeholder that accepts
      only part of the requested resize. Its hidden window must retain a one-pixel screen
      intersection. Repeat while switching workspace during the delayed check.

## Report

What felt slow (`just log`), anything that flickered, apps that misbehaved (Electron, Chrome, Finder,
JetBrains), and which defaults you'd change.
