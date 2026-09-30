#!/usr/bin/env bash
# Screenshot — drag = region, bare click (no drag) = whole screen.
# Saves to ~/Pictures/Screenshots + clipboard, then posts a notification;
# clicking the notification opens the shot in tensaku.
#
#   usage: screenshot.sh [full]   # "full" skips the picker (tests/scripts)
set -u

for dep in grim slurp wl-copy notify-send; do
    command -v "$dep" >/dev/null 2>&1 || {
        hyprctl notify 3 5000 'rgba(ff4444ff)' "Screenshot needs $dep: grim slurp wl-clipboard libnotify"
        exit 1
    }
done

# pressing Print again while a selection is open cancels it
if pgrep -x slurp >/dev/null 2>&1; then
    pkill -x slurp
    exit 0
fi

geom=""
if [ "${1:-}" != "full" ]; then
    # Escape (or the cancel above) exits non-zero → quit quietly
    geom="$(slurp)" || exit 0
    # A bare click comes back as a tiny rectangle (0x0 / 1x1 …). Anything
    # under 20px² counts as "clicked, not dragged" → take the whole screen.
    if [[ "$geom" =~ ([0-9]+)x([0-9]+) ]]; then
        w=$((10#${BASH_REMATCH[1]}))
        h=$((10#${BASH_REMATCH[2]}))
        if [ $((w * h)) -lt 20 ]; then
            geom=""
        fi
    fi
fi

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

if [ -n "$geom" ]; then
    grim -g "$geom" "$file"
else
    grim "$file"
fi || {
    hyprctl notify 3 4000 'rgba(ff4444ff)' "Screenshot failed: $file"
    exit 1
}

wl-copy < "$file"

# notify-send -A blocks until quickshell's pill invokes the action (a click
# on the notification) or the notification is dismissed; then edit the shot.
answer="$(notify-send -a Screenshot -u normal -t -1 \
    -i "$file" \
    -A edit="Edit in tensaku" \
    "Screenshot taken" "Click to edit in tensaku" 2>/dev/null)"

[ "${answer:-}" = "edit" ] && exec tensaku "$file"
exit 0
