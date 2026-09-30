#!/bin/bash

# selah-webapp-install — create a desktop launcher for a web app, so it shows
# up in the app launcher and opens as a standalone window.
#
#   webapp-install.sh                       interactive (prompts)
#   webapp-install.sh <name> <url>          interactive icon fetch
#   webapp-install.sh <name> <url> <icon>   icon: url | path | name
#   webapp-install.sh <name> <url> <icon> <custom-exec> [mime-types]
#
# Port of omarchy/bin/omarchy-webapp-install. Deliberately kept: every
# validation helper below is a fix for a specific bug (see the comments on
# each — require_plain_name and desktop_string_escape in particular stop
# path traversal and desktop-entry injection). Changed from omarchy:
#   * gum (interactive prompt UI) is not installed here -> plain read
#   * omarchy-launch-webapp -> this directory's webapp-launch.sh, by
#     absolute path, because ~/.local/bin is not on $PATH

set -e

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LAUNCHER="$SELF_DIR/webapp-launch.sh"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"

safe_icon_name() {
    printf '%s\n' "$1" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//'
}

require_plain_name() {
    # The name becomes a filename. A slash would turn it into directory levels,
    # so the launcher lands somewhere webapp-remove cannot address and the app
    # is stuck in the launcher; a leading ../ leaves the applications directory
    # altogether. Refuse rather than silently renaming what the user typed --
    # most often it is a URL entered in the name field.
    if [[ $1 == */* ]]; then
        echo "App name cannot contain '/': $1"
        exit 1
    fi
}

icon_name_from_ref() {
    local ref="$1" name
    name=$(basename "$ref")
    if [[ $name == *.* ]]; then
        safe_icon_name "${name%.*}"
    else
        printf '%s\n' "$name"
    fi
}

install_user_icon() {
    local source="$1" name="$2" ext="${source##*.}"
    [[ $ext == "$source" ]] && ext="png"
    mkdir -p "$ICON_DIR"
    cp "$source" "$ICON_DIR/$name.$ext"
    normalize_icon "$ICON_DIR/$name" "$ext"
    gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
    printf '%s\n' "$name"
}

# Extension for a downloaded icon, taken from the bytes that actually
# arrived rather than assumed. Plenty of sites ship an SVG icon (news.ycombinator.com
# does), and a file named .png that is really an SVG is one an icon loader
# may decline — which would waste the whole point of fetching it. An empty
# result means "this is not an image".
ext_for_mime() {
    case "$1" in
    image/svg+xml) printf 'svg' ;;
    image/jpeg) printf 'jpg' ;;
    image/x-icon | image/vnd.microsoft.icon) printf 'ico' ;;
    image/webp) printf 'webp' ;;
    image/*) printf 'png' ;;
    *) printf '' ;;
    esac
}

# quickshell's theme scan only picks up png and svg (measured live in the
# launcher: .ico and .webp resolve to nothing until re-encoded, and a miss
# is cached per icon name until quickshell restarts). Re-encode anything
# else to png on arrival; svg stays svg. On failure keep whatever arrived
# rather than delete the only copy. Never prints to stdout — call sites
# capture stdout as the icon name.
normalize_icon() {
    local stem=$1 ext=$2 tmp="$1.tmp.png"
    [[ $ext == png || $ext == svg ]] && return 0
    command -v ffmpeg >/dev/null 2>&1 || return 0
    if ffmpeg -y -loglevel error -i "$stem.$ext" "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
        mv -f "$tmp" "$stem.png"
        rm -f "$stem.$ext"
    else
        rm -f "$tmp"
    fi
    return 0
}

# $1 = url, $2 = destination STEM (no extension). Leaves nothing behind
# unless a real, non-empty image landed: the response is written to .part,
# typed, then swapped into place under its own extension.
download_icon() {
    local stem=$2 ext stale
    if ! curl -fsSL --max-time 10 -o "$stem.part" "$1" 2>/dev/null || [[ ! -s $stem.part ]]; then
        rm -f "$stem.part"
        return 1
    fi
    ext=$(ext_for_mime "$(file -b --mime-type "$stem.part")")
    if [[ -z $ext ]]; then
        rm -f "$stem.part"
        return 1
    fi
    # a previous attempt at this name may have landed a different extension
    for stale in "$stem".*; do
        if [[ -e $stale && $stale != "$stem.part" ]]; then
            rm -f "$stale"
        fi
    done
    mv "$stem.part" "$stem.$ext"
    normalize_icon "$stem" "$ext"
}

# Chromium --app= treats javascript:, file:, and data: as a document to run.
# Prefix schemeless input with https as before, then refuse anything that is
# not http(s).
normalize_webapp_url() {
    local url=$1
    if [[ ! $url =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]]; then
        url="https://$url"
    fi
    printf '%s' "$url"
}

# Raw whitespace must be percent-encoded in a URL. Refuse it before serializing
# the desktop entry; before Exec argument quoting, it also split browser flags
# and additional URLs into separate arguments. Schemes are case-insensitive.
require_http_url() {
    # returns 1 rather than exiting: webapp-install.sh calls it inside a
    # re-prompt loop interactively (set -e still aborts the non-interactive
    # call sites, which is what we want there)
    local url=$1
    if [[ $url =~ [[:space:]] ]]; then
        echo "Error: web app URL must not contain whitespace." >&2
        return 1
    fi
    if [[ ! ${url,,} =~ ^https?:// ]]; then
        echo "Error: web app URL must be http or https." >&2
        return 1
    fi
}

fetch_site_icon() {
    local site_url="$1" dest="$2"
    local origin page icon_url
    origin=$(sed -E 's|^(https?://[^/]+).*|\1|' <<<"$site_url")

    # Prefer the site's own high-res icon (apple-touch-icon is typically
    # 180px+), then rel="icon" (plenty of sites ship only that), then the
    # well-known path, then Google's favicon service as a last resort.
    page=$(curl -fsSL --max-time 5 "$site_url" 2>/dev/null | head -c 100000 | tr '\n' ' ')
    icon_url=$(grep -oiE "<link[^>]*rel=[\"'][^\"']*icon[^\"']*[\"'][^>]*>" <<<"$page" |
        grep -oiE "href=[\"'][^\"']+" | head -1 | sed -E "s/^href=[\"']//")

    # `rel="icon" href="data:,"` (example.com ships exactly this) is a
    # deliberate "no icon here" marker — writing it out would save a file
    # named .png that is not an image, and the mime check below would then
    # reject it anyway.
    case $icon_url in
    data:* | javascript:* | '') icon_url="" ;;
    esac

    case $icon_url in
    http://* | https://*) ;;
    //*) icon_url="https:$icon_url" ;;
    /*) icon_url="$origin$icon_url" ;;
    ?*) icon_url="$origin/$icon_url" ;;
    esac

    { [[ -n $icon_url ]] && download_icon "$icon_url" "$dest"; } ||
        download_icon "$origin/apple-touch-icon.png" "$dest" ||
        download_icon "https://www.google.com/s2/favicons?domain=${site_url}&sz=256" "$dest"
}

desktop_string_escape() {
    # Desktop Entry "string" value (freedesktop Desktop Entry Spec, "Value
    # types"): a raw newline would start a new key line and let a value inject
    # a second Exec=. Escape backslash first, then tab/CR/LF and a leading
    # space. Every value written into the .desktop file passes through here.
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//$'\t'/\\t}
    value=${value//$'\r'/\\r}
    value=${value//$'\n'/\\n}
    [[ $value == " "* ]] && value="\\s${value# }"
    printf '%s' "$value"
}

desktop_exec_arg() {
    # One Exec argument, double-quoted per the freedesktop Exec spec: inside
    # quotes " ` $ \ take a backslash and a literal % becomes %%.
    local escaped
    escaped=$(printf '%s' "$1" |
        sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/`/\\`/g' -e 's/\$/\\$/g' -e 's/%/%%/g')
    printf '"%s"' "$escaped"
}

# interactive prompts ------------------------------------------------
prompt() {
    # $1 = prompt text, $2 = placeholder/example. Re-prompts until non-empty,
    # and survives a closed terminal (EOF) instead of looping forever.
    local label=$1 hint=$2 reply
    while :; do
        read -r -p "$label> " reply || { echo; exit 1; }
        if [ -n "$reply" ]; then printf '%s' "$reply"; return 0; fi
        [ -n "$hint" ] && printf '  (e.g. %s)\n' "$hint" >&2
    done
}

if (( $# < 3 )); then
    printf '\n\033[32mCreate a web app launcher\033[0m\n'
    printf 'It will appear in the app launcher alongside your installed apps.\n\n'

    while :; do
        APP_NAME=$(prompt "Name" "My favorite web app")
        if [[ $APP_NAME == */* ]]; then
            printf '\033[31mApp name cannot contain "/"\033[0m\n' >&2
            continue
        fi
        break
    done

    while :; do
        APP_URL=$(prompt "URL" "https://example.com")
        APP_URL=$(normalize_webapp_url "$APP_URL")
        if ! require_http_url "$APP_URL"; then continue; fi
        break
    done

    # Try to fetch the site's icon automatically first.
    mkdir -p "$ICON_DIR"
    ICON_VALUE=$(safe_icon_name "$APP_NAME")
    if fetch_site_icon "$APP_URL" "$ICON_DIR/$ICON_VALUE"; then
        gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
        ICON_REF="$ICON_VALUE"
        printf '  icon: fetched from the site\n'
    else
        printf '  could not fetch an icon from the site\n' >&2
        ICON_REF=$(prompt "Icon URL or icon name" "")
    fi

    CUSTOM_EXEC=""
    MIME_TYPES=""
    INTERACTIVE_MODE=true
else
    APP_NAME="$1"
    APP_URL=$(normalize_webapp_url "$2")
    require_http_url "$APP_URL"
    ICON_REF="$3"
    CUSTOM_EXEC="${4:-}"  # Optional custom exec command
    MIME_TYPES="${5:-}"   # Optional mime types
    INTERACTIVE_MODE=false
fi

if [[ -z $APP_NAME || -z $APP_URL ]]; then
    echo "You must set app name and app URL!"
    exit 1
fi

require_plain_name "$APP_NAME"

if [[ -z $ICON_REF ]]; then
    ICON_VALUE=$(safe_icon_name "$APP_NAME")
    mkdir -p "$ICON_DIR"
    if fetch_site_icon "$APP_URL" "$ICON_DIR/$ICON_VALUE"; then
        gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
    else
        # No icon anywhere — no <link icon>, no apple-touch-icon, and every
        # remote fetch failed (Google's favicon service is unreachable from
        # some networks). Building the launcher anyway beats refusing to
        # build it, so fall back to a generic icon the theme already ships.
        printf '  no site icon found, using the generic browser icon\n' >&2
        ICON_VALUE="web-browser"
    fi
elif [[ $ICON_REF =~ ^https?:// ]]; then
    ICON_VALUE=$(safe_icon_name "$APP_NAME")
    mkdir -p "$ICON_DIR"
    if download_icon "$ICON_REF" "$ICON_DIR/$ICON_VALUE"; then
        gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
    else
        printf '  could not download that icon, using the generic browser icon\n' >&2
        ICON_VALUE="web-browser"
    fi
elif [[ -f $ICON_REF ]]; then
    ICON_VALUE=$(install_user_icon "$ICON_REF" "$(safe_icon_name "$APP_NAME")")
else
    # Bundled icons live package-owned under /usr/share/icons/hicolor. Accept
    # either "HEY" or the historical "HEY.png" argument form.
    ICON_VALUE=$(icon_name_from_ref "$ICON_REF")
fi

# Default Exec quotes the URL as one Exec-spec argument. $CUSTOM_EXEC is a
# full command line, so it gets file-syntax escaping only.
if [[ -n $CUSTOM_EXEC ]]; then
    EXEC_COMMAND=$CUSTOM_EXEC
else
    EXEC_COMMAND="$LAUNCHER $(desktop_exec_arg "$APP_URL")"
fi

DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"
mkdir -p "$DESKTOP_DIR"

name_field=$(desktop_string_escape "$APP_NAME")
exec_field=$(desktop_string_escape "$EXEC_COMMAND")
icon_field=$(desktop_string_escape "$ICON_VALUE")

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$name_field
Comment=$name_field
Exec=$exec_field
Terminal=false
Type=Application
Icon=$icon_field
StartupNotify=true
EOF

[[ -n $MIME_TYPES ]] && printf 'MimeType=%s\n' "$(desktop_string_escape "$MIME_TYPES")" >>"$DESKTOP_FILE"

chmod +x "$DESKTOP_FILE"

# Without this the freedesktop cache still misses the entry, so a launcher
# built seconds ago is invisible until something else refreshes it.
update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

if [[ $INTERACTIVE_MODE == "true" ]]; then
    printf '\n\033[32m%s is ready\033[0m — find it in the app launcher.\n' "$APP_NAME"
    printf 'File: %s\n' "$DESKTOP_FILE"
fi
