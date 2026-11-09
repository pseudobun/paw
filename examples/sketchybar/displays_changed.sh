#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# After some unplugs sketchybar keeps a bar for the display that left and draws it over the
# remaining one; --reload doesn't clear it, a restart does. Restart only when its display
# count disagrees with paw's ($PAW_DISPLAYS), otherwise just refresh the workspace items.
sleep 2
n=$(sketchybar --query displays 2>/dev/null | grep -c '"arrangement-id"')
if [[ -n "${PAW_DISPLAYS:-}" && "$n" != "$PAW_DISPLAYS" ]]; then
    if command -v brew >/dev/null && brew services list 2>/dev/null | grep -q '^sketchybar .*started'; then
        brew services restart sketchybar >/dev/null 2>&1
    else
        pkill -x sketchybar; sleep 1; pgrep -x sketchybar >/dev/null || (sketchybar >/dev/null 2>&1 &)
    fi
else
    sketchybar --trigger paw_windows_change
fi
