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
- [ ] `ctrl+alt+return` zoom; `ctrl+alt+space` float (centred, 2/3); `ctrl+alt+c` float in the middle cell; `ctrl+shift+return` floats full size
- [ ] Drag a tiled window onto another tile and let go → they swap; drop elsewhere → snaps back
- [ ] Animations: smooth? Try `animation.curve: "spring"`, `durationMs: 250`, `resize: "animate"`, `enabled: false`

## Workspaces

- [ ] `ctrl+1…0` and `ralt+1…0` switch instantly; windows of other workspaces are out of sight (one pixel in the bottom-right corner)
- [ ] `ralt+shift+N` sends a window, `cmd+ctrl+N` sends and follows
- [ ] `ralt+a/d` prev/next; `hyper+n` new; `hyper+d` closes (windows go to the previous workspace)
- [ ] ⌘Tab to an app whose window is on another workspace → paw switches there
- [ ] Two displays: each shows its own workspace; `workspace N` for one shown on the other display just focuses it
- [ ] Close a window → focus stays on the same workspace (doesn't jump to another window of that app elsewhere)
- [ ] Minimise / ⌘H an app → its tile closes; restore → it comes back
- [ ] `paw quit` → every window back on screen; start again → windows return to their workspaces

## Presets and rules

- [ ] Add a `workspaces` preset (README example), then `paw arrange 1` → apps in the right tiles and sizes
- [ ] Quit the preset apps, `paw initiate` → they open and land on their workspaces, `initiate.focus` is shown
- [ ] Quit and reopen an app from a preset → it lands in its tile
- [ ] System Settings, Raycast, CleanShot float; a Brave extension popup floats, the main Brave window tiles
- [ ] `rules: [{ app: "Slack", workspace: "9" }]` → new Slack window opens on 9 without stealing focus

## Report

What felt slow (`just log`), anything that flickered, apps that misbehaved (Electron, Chrome, Finder,
JetBrains), and which defaults you'd change.
