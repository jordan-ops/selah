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
# wallhaven.cc is deliberately NOT searched through aether either: its
# `--search-wallhaven` silently ignores --ratios, --top-range and --seed
# (verified live: identical, unfiltered results with and without them), so
# the complete filter set lives in wallhaven.py beside this script. This
# script only resolves `--wallhaven` into a local file and then walks the
# unchanged pipeline below.
#
# The result is materialised as a NEW theme under ~/.config/themes/ and handed
# to switch-theme.sh — the ONE path this setup already trusts, and the same one
# every existing theme goes through:
#
#   colors.toml --toml2colors.py--> ~/.local/state/quickshell/generated/colors.json
#                                   Colors.qml watches it -> live shell recolor
#   colors.toml --global-theme.py-> kitty, foot, GTK, hypr colors.lua, btop,
#                                   chromium policy, SDDM greeter, the Firefox
#                                   profile (userChrome/userContent + prefs,
#                                   restarted by hand — Gecko has no policy
#                                   hook) and ~/.local/share/icons/
#                                   quickshell-folders (Yaru folders tinted
#                                   to the accent)
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
#   aether-apply.sh --wallhaven <query...> [wallhaven filters] [options]
#                   search wallhaven.cc, download one result, then the exact
#                   same pipeline as a local wallpaper; --add-to works too
#                   (fetch first, then add)
#   aether-apply.sh --similar <id|url> [wallhaven filters] [options]
#                   wallhaven's own "Search for similar..." instead of words:
#                   find wallpapers LIKE <id>, download one, same pipeline

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: aether-apply.sh <wallpaper> [options]
       aether-apply.sh <wallpaper> --add-to <theme>
       aether-apply.sh --wallhaven <query...> [wallhaven filters] [options]
       aether-apply.sh --similar <id|url> [wallhaven filters] [options]

  --mode <mode>      aether extraction mode (default: material)
  --light             build a light palette
  --palette '<json>'  16 hex colours; skips extraction (what the picker sends)
  --no-apply          create the theme without switching to it
  --add-to <theme>    copy the wallpaper into an existing theme's backgrounds/

wallhaven mode: search wallhaven.cc, download one result, then the SAME
pipeline as a local wallpaper — --mode/--light/--palette/--no-apply behave
identically, and --add-to is allowed (it fetches first, then adds; an add
still never touches colors.toml):
  --wallhaven <words>  every non-flag word is the query; wallhaven syntax
                      (~tag, -exclude, id:, @user, #id, like:<id>) passes
                      through
  --similar <ref>     wallpapers LIKE this one — wallhaven's own "Search for
                      similar..." (a wallpaper id or its wallhaven URL).
                      Replaces the query words rather than adding to them,
                      combines with every filter below, and needs no API key
  --categories 111    general/anime/people bitmask (default: 111)
  --purity 100        sfw/sketchy/nsfw bitmask (default: 100; sketchy and
                      nsfw need an API key)
  --sorting <how>     date_added|relevance|random|views|favorites|toplist
  --order <dir>       desc (default) | asc
  --top-range <r>     1d|3d|1w|1M|1y|all (only with --sorting toplist)
  --at-least WxH      minimum resolution, e.g. 2560x1440
  --ratios <list>     comma list of aspect ratios, e.g. 16x9,21x9
  --colors <list>     comma list of colours, rrggbb or #rrggbb
  --page N            results page (default: 1)
  --seed <str>        forwarded to the API's random sorting
  --pick <p>          first | random (default) | N — which result to take.
                      Chosen CLIENT-SIDE from the fetched page: wallhaven
                      currently ignores server-side seeds (checked live), so
                      --seed cannot make the random pick reproducible
  --api-key <key>     wallhaven API key (default: $WALLHAVEN_API_KEY).
                      Only sketchy/nsfw purity and the account's default
                      filters need it — --similar does not
EOF
    exit 1
}

[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage ;; esac

MODE="material"
LIGHT=""
NO_APPLY=0
PALETTE=""
ADD_TO=""

# --wallhaven replaces the <wallpaper> argument: every remaining word that is
# not a known flag becomes the search query, so `--wallhaven mountains night
# --at-least 2560x1440` works with no quoting even mid-query. --similar
# implies the same mode (it SEARCHES by similarity instead of asking for
# words) but is left for the loop below to read, which is why only
# --wallhaven is consumed here. The wallpaper itself is fetched further
# down, right before the shared [ -f "$WP" ] check.
WH_MODE=0
WH_QUERY=""
WH_SIMILAR=""
WH_ARGS=()
WH_KEY=""
PICK="random"
case "$1" in
    --wallhaven) WH_MODE=1; shift ;;
    --similar)   WH_MODE=1 ;;      # flag, value and all stay for the loop
    *)           WP="$1"; shift ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)    [ $# -ge 2 ] || usage; MODE="$2"; shift 2 ;;
        --light)   LIGHT="--light-mode"; shift ;;
        --no-apply) NO_APPLY=1; shift ;;
        --palette) [ $# -ge 2 ] || usage; PALETTE="$2"; shift 2 ;;
        --add-to)  [ $# -ge 2 ] || usage; ADD_TO="$2"; shift 2 ;;
        --categories|--purity|--sorting|--order|--top-range|--at-least|--ratios|--colors|--page|--seed)
            # Collected verbatim and replayed into `wallhaven.py search`, so
            # the names here and there cannot drift. Only meaningful with
            # --wallhaven; used otherwise they are a mistake, and a mistake
            # should print usage instead of vanishing silently.
            [ "$WH_MODE" -eq 1 ] || usage
            [ $# -ge 2 ] || usage
            WH_ARGS+=("$1" "$2")
            shift 2 ;;
        --similar)
            # --similar leading the command line already set WH_MODE, so
            # this guard only catches the other spelling: a wallpaper path
            # followed by --similar is a mistake, not a mix of the two.
            [ "$WH_MODE" -eq 1 ] || usage
            [ $# -ge 2 ] || usage
            WH_SIMILAR="$2"
            shift 2 ;;
        --pick)
            [ "$WH_MODE" -eq 1 ] || usage
            [ $# -ge 2 ] || usage
            PICK="$2"
            shift 2 ;;
        --api-key)
            [ "$WH_MODE" -eq 1 ] || usage
            [ $# -ge 2 ] || usage
            WH_ARGS+=("--apikey" "$2")   # wallhaven.py spells the flag --apikey
            WH_KEY="$2"                  # download needs the key too: the
                                         # /w/<id> record of a sketchy/nsfw
                                         # result is guest-blocked without it
            shift 2 ;;
        -h|--help) usage ;;
        *)
            if [ "$WH_MODE" -eq 1 ]; then
                # Double-dash words are flags and a typo must be loud;
                # everything else — including wallhaven's single-dash
                # -exclude terms — is query text.
                case "$1" in --*) usage ;; esac
                WH_QUERY="${WH_QUERY:+$WH_QUERY }$1"
                shift
            else
                usage
            fi ;;
    esac
done

if [ "$WH_MODE" -eq 1 ] && [ -z "$WH_QUERY" ] && [ -z "$WH_SIMILAR" ]; then
    usage    # --wallhaven with nothing to search for
fi

# --similar and query words both mean "what to search for"; wallhaven.py
# rejects the mix too, but failing here says so before any API call.
if [ -n "$WH_SIMILAR" ] && [ -n "$WH_QUERY" ]; then
    echo "aether-apply: --similar replaces the words — pass one, not both" >&2
    exit 1
fi

HOME_DIR="${HOME:?HOME is not set}"
THEMES_DIR="$HOME_DIR/.config/themes"
SWITCH="$HOME_DIR/.config/quickshell/scripts/switch-theme.sh"
MARKER=".aether-generated"
PY="python3"
# wallhaven.py sits beside this script; the $HOME/.config/quickshell/scripts
# spelling matches how SWITCH and toml2colors.py are found, and
# ~/.config/quickshell IS this repo (a symlink), so it is the copy edited here.
WH_PY="$HOME_DIR/.config/quickshell/scripts/wallhaven.py"

command -v aether >/dev/null 2>&1 || {
    echo "aether-apply: 'aether' is not on PATH (yay -S aether)" >&2; exit 1
}
command -v "$PY" >/dev/null 2>&1 || { echo "aether-apply: python3 missing" >&2; exit 1; }

# --- resolve the wallpaper ---------------------------------------------------
# A local path has to exist already; --wallhaven turns a search into one
# first. Either way the pipeline below sees a plain existing file, and the
# [ -f "$WP" ] check stays a single shared guard for both modes.
if [ "$WH_MODE" -eq 1 ]; then
    [ -f "$WH_PY" ] || { echo "aether-apply: missing $WH_PY" >&2; exit 1; }

    # Validate --pick BEFORE the search so a typo costs no API call.
    case "$PICK" in
        first|random) ;;
        ''|*[!0-9]*)
            echo "aether-apply: --pick wants first, random or a number: $PICK" >&2
            exit 1 ;;
    esac

    # One search, one page: the count and the chosen id are read from the
    # SAME document, so pick N can never drift from the list that named it.
    # wallhaven.py owns both spellings — words and `--similar` (which is
    # wallhaven's like:<id> query plus its own challenge handling) — so
    # everything else (filters, pick, download) is identical either way.
    if [ -n "$WH_SIMILAR" ]; then
        WH_CMD=(search --similar "$WH_SIMILAR")
        WH_DESC="for wallpapers like $WH_SIMILAR"
    else
        WH_CMD=(search "$WH_QUERY")
        WH_DESC="for '$WH_QUERY'"
    fi
    if ! WH_RESULT="$("$PY" "$WH_PY" "${WH_CMD[@]}" --json \
            "${WH_ARGS[@]}")"; then
        echo "aether-apply: wallhaven search failed $WH_DESC" >&2
        exit 1
    fi

    COUNT="$(printf '%s' "$WH_RESULT" | "$PY" -c \
        'import json,sys; print(len(json.load(sys.stdin).get("results", [])))')"
    [ "$COUNT" -ge 1 ] || {
        echo "aether-apply: wallhaven found nothing $WH_DESC" >&2; exit 1; }

    # --pick is resolved CLIENT-SIDE on the fetched page: wallhaven currently
    # regenerates random seeds server-side (checked live — it ignores even
    # its own issued seeds), so a server-side shuffle could not be
    # reproduced anyway. --seed is still forwarded by wallhaven.py for when
    # the API honours it again.
    case "$PICK" in
        first)  IDX=1 ;;
        random) IDX=$(( (RANDOM % COUNT) + 1 )) ;;
        *)      IDX=$((10#$PICK)) ;;
    esac
    if [ "$IDX" -lt 1 ] || [ "$IDX" -gt "$COUNT" ]; then
        echo "aether-apply: --pick $IDX outside the 1..$COUNT results" >&2
        exit 1
    fi

    IDX0=$((IDX - 1))
    WH_ID="$(printf '%s' "$WH_RESULT" | "$PY" -c \
        "import json,sys; print(json.load(sys.stdin)['results'][$IDX0]['id'])")"
    echo "aether-apply: wallhaven pick $IDX/$COUNT -> $WH_ID"
    WH_DL=(download "$WH_ID")
    if [ -n "$WH_KEY" ]; then
        WH_DL+=(--apikey "$WH_KEY")
    fi
    if ! WP="$("$PY" "$WH_PY" "${WH_DL[@]}")"; then
        echo "aether-apply: wallhaven download failed for $WH_ID" >&2
        exit 1
    fi
fi

[ -f "$WP" ] || { echo "aether-apply: no such wallpaper: $WP" >&2; exit 1; }

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
