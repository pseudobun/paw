#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# On some unplugs sketchybar drops every bar (0 displays) or keeps one for the display that
# left; --reload doesn't help, a restart does. Restart at once on 0, after a short grace period
# when the count still disagrees with paw's ($PAW_DISPLAYS); otherwise just refresh.
log="$HOME/Library/Logs/paw-displays.log"
count() { sketchybar --query displays 2>/dev/null | grep -c '"arrangement-id"'; }
n=$(count)
for _ in 1 2 3 4; do
    [[ -z "${PAW_DISPLAYS:-}" || "$n" == "$PAW_DISPLAYS" || "$n" == 0 ]] && break
    sleep 0.5; n=$(count)
done
if [[ -n "${PAW_DISPLAYS:-}" && "$n" != "$PAW_DISPLAYS" ]]; then
    echo "$(date '+%F %T') paw $PAW_DISPLAYS, sketchybar $n: restarting sketchybar" >>"$log"
    label=$(launchctl list 2>/dev/null | awk '/sketchybar/ { print $3; exit }')
    if [[ -n "$label" ]]; then
        launchctl kickstart -k "gui/$(id -u)/$label"
    else
        pkill -x sketchybar; sleep 0.5; sketchybar >/dev/null 2>&1 &
    fi
else
    echo "$(date '+%F %T') paw $PAW_DISPLAYS, sketchybar $n: ok" >>"$log"
    sketchybar --trigger paw_windows_change
fi
