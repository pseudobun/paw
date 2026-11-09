#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# sketchybar rebuilds its bars on every display change and usually comes back by itself, so a
# restart while macOS is still reconfiguring only adds time. Sometimes, though, it settles on the
# wrong displays: a leftover bar for one that left (DirectDisplayID 0) drawn over another, or no
# bar on new ones. Only a restart fixes that. So: give it up to ~10 s to match paw's displays
# ($PAW_DISPLAYS), check again a little later, and restart when it still doesn't.
log="$HOME/Library/Logs/paw-displays.log"
want="${PAW_DISPLAYS:-}"
state() { sketchybar --query displays 2>/dev/null | tr -d ' \t\n'; }
good() {
    local s n; s="$(state)"
    n=$(grep -o '"arrangement-id"' <<<"$s" | wc -l | tr -d ' ')
    [[ -z "$want" ]] || { [[ "$n" == "$want" ]] && ! grep -q '"DirectDisplayID":0[,}]' <<<"$s"; }
}
settle() { for _ in $(seq 1 20); do good && return 0; sleep 0.5; done; return 1; }
restart() {
    echo "$(date '+%F %T') paw $want, sketchybar $(grep -o '"arrangement-id"' <<<"$(state)" | wc -l | tr -d ' '): restarting sketchybar" >>"$log"
    local label; label=$(launchctl list 2>/dev/null | awk '/sketchybar/ { print $3; exit }')
    if [[ -n "$label" ]]; then launchctl kickstart -k "gui/$(id -u)/$label"
    else pkill -x sketchybar; sleep 0.5; sketchybar >/dev/null 2>&1 & fi
}
if settle; then
    sketchybar --trigger paw_windows_change
    sleep 4
    good || { restart; exit 0; }
    echo "$(date '+%F %T') paw $want: ok" >>"$log"
else
    restart
fi
