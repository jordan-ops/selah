#!/usr/bin/env bash
# aether-apply.sh — bridge: aether colour extraction -> this setup's theme pipeline.
#
# aether's ONLY job here is picking a palette. Nothing it produces ever points
# an app config at itself: the GUI's `--generate` path (which would symlink
# kitty/hypr/GTK and own the whole desktop) is deliberately not used.
#
# Instead the palette — whether freshly extracted or handed in by the picker
# after the user's colour edits — is pushed through `aether --show-variables`,
# which runs aether's own palette->role mapping and returns exactly the keys
# colors.toml holds (verified key-for-key against `--generate`'s output). So
# the derived shades, accent and orange/brown hues are aether's, not ours.
#
# The result is materialised as a NEW theme under ~/.config/themes/ and handed
# to switch-theme.sh — the ONE path this setup already trusts, and the same one
# every existing theme goes through:
#
#   colors.toml --toml2colors.py--> ~/.local/state/quickshell/generated/colors.json
#                                   Colors.qml watches it -> live shell recolor
#   colors.toml --global-theme.py-> kitty, foot, GTK, hypr colors.lua, btop,
#                                   chromium policy, SDDM greeter
#   backgrounds/default.*         -> ~/.local/state/quickshell/current-wallpaper
#                                   Background.qml crossfades to it
#
# CREATE, don't clobber:
#   * a directory that is not ours is never written to — a slug that collides
#     with a hand-made theme ("nord.jpg") makes us pick a free numbered name
#     instead ("aether-nord-2"), so ~/.config/themes/nord is untouchable.
#   * the same wallpaper re-themed updates the theme it already created
#     (.aether-generated records the source path), so nudging saturation and
#     re-creating does not litter the library with copies.
#   * --no-apply creates the theme and stops there; switching is opt-in.
#
# Usage:
#   aether-apply.sh <wallpaper> [--mode <mode>] [--light] [--no-apply]
#                   [--palette '<json-array-of-16>']
#   aether-apply.sh <wallpaper> --add-to <theme>
#                   add the wallpaper to an existing theme's backgrounds/
#                   (never touches colors.toml — an add is never a change)

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: aether-apply.sh <wallpaper> [options]
       aether-apply.sh <wallpaper> --add-to <theme>

  --mode <mode>      aether extraction mode (default: material)
  --light             build a light palette
  --palette '<json>'  16 hex colours; skips extraction (what the picker sends)
  --no-apply          create the theme without switching to it
  --add-to <theme>    copy the wallpaper into an existing theme's backgrounds/
EOF
    exit 1
}

[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage ;; esac
WP="$1"
shift

MODE="material"
LIGHT=""
NO_APPLY=0
PALETTE=""
ADD_TO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)    [ $# -ge 2 ] || usage; MODE="$2"; shift 2 ;;
        --light)   LIGHT="--light-mode"; shift ;;
        --no-apply) NO_APPLY=1; shift ;;
        --palette) [ $# -ge 2 ] || usage; PALETTE="$2"; shift 2 ;;
        --add-to)  [ $# -ge 2 ] || usage; ADD_TO="$2"; shift 2 ;;
        -h|--help) usage ;;
        *)         usage ;;
    esac
done

HOME_DIR="${HOME:?HOME is not set}"
THEMES_DIR="$HOME_DIR/.config/themes"
SWITCH="$HOME_DIR/.config/quickshell/scripts/switch-theme.sh"
MARKER=".aether-generated"
PY="python3"

[ -f "$WP" ] || { echo "aether-apply: no such wallpaper: $WP" >&2; exit 1; }
command -v aether >/dev/null 2>&1 || {
    echo "aether-apply: 'aether' is not on PATH (yay -S aether)" >&2; exit 1
}
command -v "$PY" >/dev/null 2>&1 || { echo "aether-apply: python3 missing" >&2; exit 1; }

case "$WP" in
    *.*) EXT="${WP##*.}" ;;
    *)   EXT="jpg" ;;
esac
EXT="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"

# --- add to an existing theme ------------------------------------------------
# Widely different from "create": this is the only operation allowed to touch
# a theme it did not make, and even then it only ever drops a new file in.
if [ -n "$ADD_TO" ]; then
    DEST_DIR="$THEMES_DIR/$ADD_TO"
    [ -d "$DEST_DIR" ] || { echo "aether-apply: no such theme: $ADD_TO" >&2; exit 1; }
    BG="$DEST_DIR/backgrounds"
    [ -d "$BG" ] || BG="$DEST_DIR/wallpapers"
    mkdir -p "$BG"

    base="$(basename "$WP")"
    stem="${base%.*}"
    dest="$BG/$base"
    n=2
    while [ -e "$dest" ]; do
        if cmp -s "$WP" "$dest"; then
            echo "aether-apply: '$ADD_TO' already has $base"
            exit 0
        fi
        dest="$BG/$stem-$n.$EXT"
        n=$((n + 1))
    done
    cp -f "$WP" "$dest"
    echo "aether-apply: added $(basename "$dest") to '$ADD_TO'"
    exit 0
fi

[ -f "$SWITCH" ] || { echo "aether-apply: missing $SWITCH" >&2; exit 1; }

# --- name the theme after the wallpaper -------------------------------------
# Wallpaper basenames can collide with a hand-made theme ("nord.jpg" must never
# land in ~/.config/themes/nord), so we only ever adopt a directory that is
# either free or one we created from this very wallpaper.
# Slugs are forced to [a-z0-9-] because the name also becomes a btop theme
# filename and a global-theme.py word.
base="$(basename "$WP")"
base="${base%.*}"
slug="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-*//; s/-*$//')"
[ -n "$slug" ] || slug="wallpaper"

same_as_wp() {   # did we already theme THIS file here?
    [ -f "$1/$MARKER" ] && [ "$(cat "$1/$MARKER")" = "$WP" ] && return 0
    for f in "$1"/backgrounds/default.* "$1"/wallpapers/default.*; do
        [ -f "$f" ] && cmp -s "$WP" "$f" && return 0
    done
    return 1
}

THEME_NAME="aether-$slug"
n=2
while [ -d "$THEMES_DIR/$THEME_NAME" ]; do
    if same_as_wp "$THEMES_DIR/$THEME_NAME"; then break; fi
    THEME_NAME="aether-$slug-$n"
    n=$((n + 1))
    [ "$n" -gt 200 ] && { echo "aether-apply: cannot place '$slug'" >&2; exit 1; }
done
TARGET="$THEMES_DIR/$THEME_NAME"

# --- palette -> colours ------------------------------------------------------
# `--palette` is the palette the picker is displaying, so the swatch strip you
# approve is byte-for-byte the palette that lands. Without it (standalone use)
# we extract here with --mode/--light.
if [ -z "$PALETTE" ]; then
    PALETTE="$(aether --extract-palette "$WP" --extract-mode "$MODE" $LIGHT --json \
        | "$PY" -c 'import json,sys; d=json.load(sys.stdin); c=d.get("colors") or []; \
sys.exit("aether-apply: extract returned no colours") if len(c)<16 else None; \
print(json.dumps(c[:16]))')"
fi

VARS_JSON="$(aether --show-variables "$PALETTE" $LIGHT --json)"
[ -n "$VARS_JSON" ] || { echo "aether-apply: aether --show-variables produced nothing" >&2; exit 1; }

# --- stage the theme ---------------------------------------------------------
# The wallpaper is copied to a temp file OUTSIDE the destination first:
# re-applying a file that already lives in backgrounds/ would otherwise delete
# its own source when the directory is cleared below.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cp -f "$WP" "$TMP"

mkdir -p "$TARGET/backgrounds"
printf '%s' "$WP" > "$TARGET/$MARKER"

# Exactly one default.*, so switch-theme.sh deterministically picks it (its
# rule: default.* first, else alphabetically first image). Other images added
# with `--add-to` are left alone — they are that theme's library now.
rm -f "$TARGET/backgrounds"/default.*
cp -f "$TMP" "$TARGET/backgrounds/default.$EXT"

# colors.toml is regenerated through a temp file: a failed aether call must
# never truncate a theme that is currently in use.
#
# The JSON is handed over by path, not by pipe: a command that also carries a
# <<heredoc gets its stdin replaced by that heredoc, so `printf | python <<EOF`
# silently feeds the script to itself instead of the data.
VARS_TMP="$(mktemp)"
CT_TMP="$(mktemp)"
trap 'rm -f "$TMP" "$VARS_TMP" "$CT_TMP"' EXIT
printf '%s' "$VARS_JSON" > "$VARS_TMP"
"$PY" - "$VARS_TMP" "$CT_TMP" <<'PYEOF'
import json, sys

# The five keys aether's own colors.toml leaves out (theme_type is `mode` here;
# the rest are aliases of color0/7/8/15 that nothing reads).
DROP = {"black", "bright_black", "bright_white", "white", "theme_type"}
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
pairs = [(k, v) for k, v in doc.items() if k not in DROP and isinstance(v, str)]
# `mode` is load-bearing and aether writes it first — keep that ordering.
pairs.sort(key=lambda kv: kv[0] != "mode")

with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write("# Generated by aether-apply.sh (aether palette -> colors.toml).\n")
    fh.write("# Semantic names mirror Omarchy's theme color system; the\n")
    fh.write("# color0-15 ANSI slots are kept for tools that still read them.\n")
    for key, val in pairs:
        fh.write(f"{key} = {json.dumps(val)}\n")
PYEOF

grep -q '^background = ' "$CT_TMP" || {
    echo "aether-apply: generated colours.toml has no background" >&2; exit 1;
}
mv -f "$CT_TMP" "$TARGET/colors.toml"
trap 'rm -f "$TMP"' EXIT

# Drop the cached derived palette so switch-theme.sh re-runs toml2colors.py.
# (It normally gates on "colors.toml newer than cache" — deleting is simply
# unambiguous, and the file is regenerable.)
rm -f "$TARGET/quickshell/colors.json"

echo "aether-apply: created theme '$THEME_NAME'"

# 2. Run the normal theme switch: colors.json, wallpaper crossfade, and the
#    parallel kitty/hypr/GTK/foot/chromium/SDDM retint.
if [ "$NO_APPLY" -eq 1 ]; then
    # switch-theme.sh is what normally derives quickshell/colors.json, but the
    # bar previews every theme's copy and logs a FileView error for any theme
    # that is missing one. Deriving it here means a created-but-not-applied
    # theme is indistinguishable from an applied one.
    mkdir -p "$TARGET/quickshell"
    "$PY" "$HOME_DIR/.config/quickshell/scripts/toml2colors.py" \
        "$TARGET/colors.toml" "$TARGET/quickshell/colors.json" || true
    echo "aether-apply: not applying (--no-apply)"
    exit 0
fi
exec bash "$SWITCH" "$THEME_NAME"
