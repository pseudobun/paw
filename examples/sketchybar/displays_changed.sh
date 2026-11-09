#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# After some unplugs sketchybar keeps a bar for the display that left and draws it over the
# remaining one; --reload doesn't clear it, a restart does. Restart only when sketchybar still
# disagrees with paw ($PAW_DISPLAYS) after giving it time to catch up; otherwise just refresh.
log="$HOME/Library/Logs/paw-displays.log"
count() { sketchybar --query displays 2>/dev/null | grep -c '"arrangement-id"'; }
n=$(count)
for _ in 1 2 3 4 5 6 7 8; do
    [[ -z "${PAW_DISPLAYS:-}" || "$n" == "$PAW_DISPLAYS" ]] && break
    sleep 0.5; n=$(count)
done
if [[ -n "${PAW_DISPLAYS:-}" && "$n" != "$PAW_DISPLAYS" ]]; then
    echo "$(date '+%F %T') paw $PAW_DISPLAYS, sketchybar $n: restarting sketchybar" >>"$log"
    if command -v brew >/dev/null && brew services list 2>/dev/null | grep -q '^sketchybar .*started'; then
        brew services restart sketchybar >/dev/null 2>&1
    else
        pkill -x sketchybar; sleep 1; pgrep -x sketchybar >/dev/null || (sketchybar >/dev/null 2>&1 &)
    fi
else
    echo "$(date '+%F %T') paw $PAW_DISPLAYS, sketchybar $n: ok" >>"$log"
    sketchybar --trigger paw_windows_change
fi
