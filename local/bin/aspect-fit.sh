#!/usr/bin/env bash
# Super+F — aspect-fit "fullscreen": scales the active window to fit the
# monitor WHILE KEEPING ITS EXACT RECTANGULAR SHAPE, centered — never
# edge-to-edge (gaps + bar stay visible, margins on the sides where the
# shape doesn't match the screen). Press again to restore the previous
# size (or re-tile if it was tiled before).
#
# Geometry uses Hyprland's logical coordinates (1920x1080 @ scale 1.2 =
# 1600x900 logical); the fit box is the work area minus gaps_out.
set -u
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

AW=$(hyprctl activewindow | strip)
[ -z "$AW" ] && exit 0
ADDR=$(awk '/^Window /{print $2; exit}' <<<"$AW" | tr -d ':')
[ -z "$ADDR" ] && exit 0

read_geom() {
    AW=$(hyprctl activewindow | strip)
    read -r GW GH <<EOF
$(awk -F'[:, ]+' '/size:/{print $2, $3; exit}' <<<"$AW")
EOF
    read -r GX GY <<EOF
$(awk -F'[:, ]+' '/at:/{print $2, $3; exit}' <<<"$AW")
EOF
    GF=$(awk '/floating:/{print $2; exit}' <<<"$AW")
    GFS=$(awk '/fullscreen:/{print $2; exit}' <<<"$AW")
    GFS=${GFS:-0}
}
read_geom

ST="/tmp/hl-aspectfit-$ADDR"

# --- toggle OFF: restore previous size / re-tile ---
if [ -f "$ST" ]; then
    read -r OW OH OF <"$ST"
    rm -f "$ST"
    if [ "$OF" = "0" ]; then
        # was tiled before → unfloat; layout restores slot/size exactly
        hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })' >/dev/null
    else
        # NOTE: window = "address:..." silently no-ops on this Hyprland
        # build — omit the field so it targets the active window.
        hyprctl dispatch "hl.dsp.window.resize({ x = $OW, y = $OH })" >/dev/null
        hyprctl dispatch 'hl.dsp.window.center()' >/dev/null
    fi
    exit 0
fi

# --- really-fullscreen window: leave that first, then aspect-fit ---
if [ "$GFS" != "0" ]; then
    hyprctl dispatch 'hl.dsp.window.fullscreen({ action = "toggle" })' >/dev/null
    sleep 0.2
    read_geom
fi

# fit box: focused monitor logical size minus gaps on both sides
MON=$(hyprctl monitors | strip)
read -r PW PH <<EOF
$(grep -m1 -E '^[[:space:]]+[0-9]+x[0-9]+@' <<<"$MON" | awk '{split($1,a,"x"); split(a[2],b,"@"); print a[1], b[1]}')
EOF
SC=$(grep -m1 -E '^[[:space:]]+scale:' <<<"$MON" | awk '{print $2}')
# Lua-Hyprland prints "css gap data: L T R B" here, not "int: N"
GAP=$(hyprctl getoption general:gaps_out | strip | awk '/css gap data/{print $4; exit}')
SC=${SC:-1}; GAP=${GAP:-10}
LW=$(awk -v w="$PW" -v s="$SC" 'BEGIN{printf "%d", w/s}')
LH=$(awk -v h="$PH" -v s="$SC" 'BEGIN{printf "%d", h/s}')
BW=$((LW - 2 * GAP)); BH=$((LH - 2 * GAP))

read -r TW TH <<EOF
$(awk -v cw="$GW" -v ch="$GH" -v bw="$BW" -v bh="$BH" 'BEGIN{
    if (cw <= 0 || ch <= 0) exit
    s = bw/cw; if (bh/ch < s) s = bh/ch
    printf "%d %d", cw*s, ch*s
}')
EOF
[ -z "${TW:-}" ] && exit 1

# remember original size + floating state for the toggle-off
echo "$GW $GH $GF" >"$ST"

if [ "$GF" = "0" ]; then
    hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })' >/dev/null
    # the float's default-size transition would otherwise clobber the
    # resize below (observed: fit size lost, 700x500 stuck)
    sleep 0.25
fi
# window = "address:..." silently no-ops on this build → target active.
OUT=$(hyprctl dispatch "hl.dsp.window.resize({ x = $TW, y = $TH })")
case "$OUT" in
    *error*|*attempt*) echo "$OUT" >>/tmp/aspect-fit.log ;;
esac
hyprctl dispatch 'hl.dsp.window.center()' >/dev/null
exit 0
