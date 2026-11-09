#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# sketchybar rebuilds its bars on every display change (no bar for a few seconds, longer while
# macOS is still reconfiguring) and comes back by itself; restarting it then only adds time.
# After some unplugs, though, it keeps a bar for the display that left, drawn over another one;
# only a restart clears that. So: restart when it has more displays than paw ($PAW_DISPLAYS)
# once it has had time to settle, otherwise just refresh the workspace items.
log="$HOME/Library/Logs/paw-displays.log"
count() { sketchybar --query displays 2>/dev/null | grep -c '"arrangement-id"'; }
n=$(count)
for _ in $(seq 1 10); do
    [[ -z "${PAW_DISPLAYS:-}" || "$n" == "$PAW_DISPLAYS" ]] && break
    sleep 0.5; n=$(count)
done
if [[ -n "${PAW_DISPLAYS:-}" ]] && (( n > PAW_DISPLAYS )); then
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
