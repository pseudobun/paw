#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# sketchybar doesn't reliably follow display changes: it can keep a bar for a display that left,
# or report a new display while drawing no bar on it, and its own --query can't tell. So once
# the displays have settled (paw runs this after they have, and sketchybar has seen the same
# number, ~10 s at most), restart it: about 1.5 s, and the bars are right on every display.
log="$HOME/Library/Logs/paw-displays.log"
want="${PAW_DISPLAYS:-}"
count() { sketchybar --query displays 2>/dev/null | grep -c '"arrangement-id"'; }
for _ in $(seq 1 20); do
    [[ -z "$want" || "$(count)" == "$want" ]] && break
    sleep 0.5
done
echo "$(date '+%F %T') paw $want, sketchybar $(count): restarting sketchybar" >>"$log"
label=$(launchctl list 2>/dev/null | awk '/sketchybar/ { print $3; exit }')
if [[ -n "$label" ]]; then
    launchctl kickstart -k "gui/$(id -u)/$label"
else
    pkill -x sketchybar; sleep 0.5; sketchybar >/dev/null 2>&1 &
fi
