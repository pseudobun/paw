# Testing paw on sanctum

olympus builds and runs the unit tests; this needs your desktop with yabai.

## Setup

- [ ] stackline off: comment out `require("stackline")` in `~/.hammerspoon/init.lua`, reload Hammerspoon
- [ ] `just install`; `paw status` → stacks count, `signals: on`, `iconFont: ok`
- [ ] `paw signals list` → `paw_window_focused` … ; `paw config check` → `ok`

## Indicators

- [ ] Stack two windows (`yabai -m window --stack next`): island appears next to the window within ~0.2 s
- [ ] Icons are the same glyphs as in sketchybar's spaces; top window has the island_hi cell,
      focused window's icon is gold
- [ ] Left-half window → island on the left; right-half → on the right; full width → left
- [ ] `yabai -m window --focus stack.next` → highlight follows
- [ ] Focus another (unstacked) window → stack island fades to 0.6
- [ ] Add a third window to the stack / unstack one → island grows / shrinks; last unstack removes it
- [ ] Click an icon → that window comes forward; paw doesn't steal focus from it
- [ ] Scroll over the island → moves through the stack
- [ ] Hover an icon → title island beside it; moving away hides it
- [ ] Switch spaces → islands go with their space, the other space's stacks show
- [ ] Two displays: each display's visible space gets its stacks, on the right screen
- [ ] Drag/resize a stacked window → island follows without flicker storms (`just log` stays calm)
- [ ] Minimise / hide an app in a stack → its icon disappears
- [ ] Native full-screen app: no stray islands
- [ ] Mission Control / app switcher: islands don't get in the way

## Config, CLI, lifecycle

- [ ] `indicator.side: "insideRight"` → island moves inside the window, live on save
- [ ] `appearance.colors.accent: "0xff8698eb"` → focused icon turns wave blue
- [ ] Broken config → `paw reload` prints the error, indicators keep the old style
- [ ] `paw stacks` matches what's on screen
- [ ] `paw hide` / `paw show`
- [ ] `paw quit` → indicators gone, `paw signals list` empty
- [ ] `openAtLogin: true` → in Login Items; or `just launchd`, `kill -9` paw → restarted, signals back

Report: anything misplaced (screenshot + `paw stacks --json`), and whether it updates fast enough.
