#!/bin/bash
# Render a preview thumbnail for each theme: switch to it, stage neovim
# (hyprland/appearance.lua) + btop on a scratch workspace, grim the screen,
# and save a scaled copy to ~/.local/state/quickshell/generated/thumbnails.
#
# Usage: generate-previews.sh [theme ...]   (default: every theme)
# The original theme and workspace are restored on exit (even on error).
set -u

STATE="$HOME/.local/state/quickshell/generated/thumbnails"
THEMES_DIR="$HOME/.config/themes"
SWITCH="$HOME/.config/quickshell/scripts/switch-theme.sh"
SCRATCH_WS=8                       # only workspaces 2/3 are in use

for dep in grim ffmpeg foot hyprctl nvim btop; do
    command -v "$dep" >/dev/null || { echo "missing dependency: $dep"; exit 1; }
done
[ -x "$SWITCH" ] || { echo "missing $SWITCH"; exit 1; }

ORIG_WS=$(hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
ORIG_THEME=$(cat "$HOME/.local/state/quickshell/current-theme" 2>/dev/null || true)
TMP=$(mktemp -d /tmp/opencode/preview.XXXXXX)
PIDS=""

cleanup() {
    [ -n "$PIDS" ] && kill $PIDS 2>/dev/null
    [ -n "$ORIG_THEME" ] && bash "$SWITCH" "$ORIG_THEME" >/dev/null 2>&1
    hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIG_WS\" })" >/dev/null 2>&1
    rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$STATE"
hyprctl dispatch "hl.dsp.focus({ workspace = \"$SCRATCH_WS\" })" >/dev/null
sleep 0.5

if [ "$#" -gt 0 ]; then
    names=("$@")
else
    names=()
    for dir in "$THEMES_DIR"/*/; do names+=("$(basename "$dir")"); done
fi

count=0
for name in "${names[@]}"; do
    bash "$SWITCH" "$name" >/dev/null 2>&1 || { echo "  ! switch failed: $name"; continue; }

    foot -e nvim "$HOME/.config/hypr/appearance.lua" >/dev/null 2>&1 &
    p1=$!
    sleep 0.6
    foot -e btop >/dev/null 2>&1 &
    p2=$!
    PIDS="$p1 $p2"
    sleep 2.6                              # render + btop first paint + animations

    if grim "$TMP/$name.png" 2>/dev/null; then
        ffmpeg -v error -y -i "$TMP/$name.png" -vf "scale=640:-2" "$STATE/$name.png" \
            && { count=$((count+1)); printf '  + %s\n' "$name"; }
    else
        echo "  ! grim failed: $name"
    fi

    kill $p1 $p2 2>/dev/null; wait $p1 $p2 2>/dev/null
    PIDS=""
    sleep 0.3
done

echo "generated $count/${#names[@]} preview(s) -> $STATE"
