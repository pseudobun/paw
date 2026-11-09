# Testing paw on sanctum

olympus only builds and runs the unit tests; everything below needs a real desktop session.
Keep `just log` running in a terminal: every activation logs `N labels, M nodes, collect X ms,
visible after Y ms`. Target: **visible after < 150 ms** on a typical window.

## Setup

- [ ] `just local-cert` (once), `just install`; paw asks for Accessibility → grant it
- [ ] `paw status` → `trusted: yes`
- [ ] `~/.config/paw/config.json5` exists (template); `paw config check` → `ok`
- [ ] `just install` again → Accessibility still granted (signing identity is stable)

## Hint mode (⌘⇧Space)

- [ ] Finder: toolbar buttons, sidebar items, file rows get labels; island shows Finder's sketchybar
      glyph in gold, "Finder hint N"
- [ ] Labels look like the bar's islands (fill, 1 px border, GeistMono bold, radius ~6)
- [ ] Type the first key of a 2-key label → that key turns gold on matching labels, others fade (80 ms)
- [ ] ⌫ brings the faded labels back; a key with no label shows "no label …" in red on the island
- [ ] Last key → click. Button presses without moving the pointer (AXPress)
- [ ] Text field → caret lands in the field, pointer goes back where it was
- [ ] Finder file row: last key twice → file opens (double click)
- [ ] ⇧ + last key on a file → context menu; ⌘ + last key on a link in Safari → new tab;
      ⌥ + last key → pointer moves there, nothing clicked
- [ ] Esc closes; clicking the mouse anywhere closes; ⌘⇧Space again closes
- [ ] ⌘Tab while labels are up closes paw and switches apps
- [ ] Open a menu bar menu (click File), then ⌘⇧Space → the menu's items are labelled; pick one
- [ ] Right-click context menu open → its items are labelled
- [ ] Menu bar visible (`_HIHideMenuBar` off) → menu bar items labelled; hidden (sketchybar setup) → none
- [ ] Dock visible → Dock items labelled; autohide → none; `hint.dock: true` forces them
- [ ] `hint.menuBarExtras: true` → status items labelled (check timing in `just log`)
- [ ] Safari page: links, buttons, inputs labelled (search predicate path), timing < 150 ms
- [ ] Chrome / Brave / Arc page: same; first activation may take one retry (log says "enabled accessibility")
- [ ] Electron (Slack, Discord, VS Code, Obsidian): labels on the app UI, not just the menu bar
- [ ] System Settings, Mail, Xcode: big native trees stay < 150 ms; a long list only labels visible rows
- [ ] Two displays: labels on the right screen, island on the screen of the focused window;
      external display above/left of the built-in one; different scale factors (crisp text)
- [ ] Full-screen app (own Space): overlay shows above it
- [ ] `excludedApps: ["com.apple.Terminal"]` → hotkey does nothing in Terminal
- [ ] Hung app (e.g. `kill -STOP <pid>` of TextEdit, then hint it): paw stays responsive,
      shows "Nothing to click" after ~0.25 s; `kill -CONT` afterwards

## Search mode (⌘⇧⌥Space)

- [ ] Island centred at the top (below sketchybar), app glyph, "search <App>" placeholder, count
- [ ] Type "new" in Safari → "New Tab"-ish matches get labels, best one has gold ring + label
- [ ] Diacritics: "cevap" finds "Čevapčiči"; uppercase / Slovenian layout typing works
- [ ] ↑↓ and ⌃N/⌃P move the ring; ↵ clicks it; ⇧↵ right-clicks
- [ ] Tab → island says "labels", type a label → that match is clicked
- [ ] ⌥⌫ deletes a word, ⌘⌫ clears, ⌘V pastes
- [ ] No match → query turns red, "no match"

## Scroll mode (⌘⇧J)

- [ ] Areas numbered with wave-coloured badges; the largest is selected (gold ring), pointer moves into it
- [ ] Hold j / k → smooth scroll that eases in; release stops immediately; ⇧ while holding speeds up
- [ ] h / l scroll horizontally (wide table or code)
- [ ] d / u half a page; g top, G bottom
- [ ] 1–9 and Tab / ⇧Tab switch areas
- [ ] Wrong direction? `scroll.invert: true` fixes it (report which, so the default can change)
- [ ] Idle 5 s → closes; pointer returns to where it was
- [ ] Safari, Chrome, Finder list, Xcode editor, Terminal all scroll

## Config and CLI

- [ ] Change `appearance.colors.accent` to `"0xff8698eb"`, save → next activation uses it (no restart)
- [ ] Break the file (missing brace) → red "Config: …" island; old config keeps working; `paw reload` prints the error
- [ ] Typo key → `paw config check` warns "unknown key …"
- [ ] `hint.charset: "fjdksla"` → labels use those keys
- [ ] `hint.hotkey: ""` + skhd `hyper - f : paw hint` → works, no flash of focus change
- [ ] `paw hint` with paw not running → starts paw and opens labels
- [ ] `paw dump --delay=3` → switch to an app → JSON with elements and `ms`
- [ ] `paw icon Ghostty` → `:ghostty:`; `icons.overrides` changes it
- [ ] `openAtLogin: true` → paw in Login Items; log out / in → running
- [ ] `just launchd` → LaunchAgent loaded; `paw quit` → stays quit; crash (`kill -9`) → restarted

Report back: timings from `just log` for Finder, Safari, Chrome, Slack/VS Code, System Settings,
and anything that looked off (`paw dump > /tmp/x.json` from the app helps).
