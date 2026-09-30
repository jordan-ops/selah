#!/bin/sh
# Displays persistence for the settings app.
#
# A monitor rule is re-matched on every connect AND on every hyprctl
# reload, so a live hl.monitor apply alone is forgotten — omasettings
# wrote the laptop panel's numbers into ~/.config/hypr/monitors.lua in
# place for exactly this reason. Single-value edit of the one hl.monitor
# block the file holds (keeps the file's key alignment), first-touch .bak,
# luac -p before the temp file replaces the original, then the live apply
# (hyprctl keyword does nothing on a Lua config — eval only).
set -u

usage() { echo "Usage: set-display.sh mode|scale <value>" >&2; exit 2; }
[ $# -eq 2 ] || usage
KIND=$1
VALUE=$2

# values land inside a Lua string — refuse anything that could break out
case "$VALUE" in
  *[!A-Za-z0-9.@x-]*|'') echo "refusing value: $VALUE" >&2; exit 1 ;;
esac

HYPR_DIR="${OMASETTINGS_HYPR_DIR:-$HOME/.config/hypr}"
FILE="$HYPR_DIR/monitors.lua"
[ -f "$FILE" ] || { echo "no monitors.lua at $FILE" >&2; exit 1; }

case "$KIND" in
  mode)  KEY=mode ;;
  scale) KEY=scale ;;
  *) usage ;;
esac

# first-touch backup — never overwritten by later writes
if [ ! -f "$FILE.bak" ]; then cp -p "$FILE" "$FILE.bak"; fi

TMP="$FILE.tmp.$$"
# replace only the value after `key = "…"`, preserving the alignment of
# the original line; append-new-rules is not this script's business
sed -E "s/^([[:space:]]*${KEY}[[:space:]]*= \").*(\",)$/\1${VALUE}\2/" "$FILE" > "$TMP"

grep -qE "^[[:space:]]*${KEY}[[:space:]]*=" "$TMP" \
  || { rm -f "$TMP"; echo "no ${KEY} line in monitors.lua" >&2; exit 1; }
grep -qF "\"$VALUE\"" "$TMP" \
  || { rm -f "$TMP"; echo "${KEY} value was not replaced" >&2; exit 1; }

if command -v luac >/dev/null 2>&1; then
  luac -p "$TMP" >/dev/null 2>&1 \
    || { rm -f "$TMP"; echo "edit would not compile; monitors.lua untouched" >&2; exit 1; }
fi
mv "$TMP" "$FILE"

# apply now as well — eval is the only way monitor rules take effect live
# on a Lua config; output "" matches the file's own all-outputs rule
if [ "$KIND" = scale ]; then
  hyprctl eval "hl.monitor({ output = \"\", scale = \"$VALUE\" })" >/dev/null
else
  hyprctl eval "hl.monitor({ output = \"\", mode = \"$VALUE\" })" >/dev/null
fi
exit 0
