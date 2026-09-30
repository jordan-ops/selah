#!/bin/bash

# selah-webapp-remove — delete a web app launcher created by webapp-install.sh
#
#   webapp-remove.sh              prompts with a numbered list
#   webapp-remove.sh <name>       removes that one
#
# Port of omarchy/bin/omarchy-webapp-remove. Kept as-is: the removal targets
# are discovered by scanning for OUR launcher in Exec=, never rebuilt from the
# typed name — a name rebuilt from display text cannot reach a launcher that
# was nested in a directory, and those are exactly the stuck ones.

set -e

ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
OLD_ICON_DIR="$HOME/.local/share/applications/icons"
DESKTOP_DIR="$HOME/.local/share/applications"
# the only marker that identifies a launcher as ours — see the scan below
SELF_LAUNCHER="webapp-launch.sh"

WEB_APPS=()
WEB_APP_PATHS=()

while IFS= read -r -d '' file; do
    # Only our own launchers: anything Exec=ing webapp-launch.sh. Matching on
    # the script name rather than on a URL pattern means an ordinary app that
    # happens to open a web URL is never picked up and deleted.
    if grep -q "^Exec=.*${SELF_LAUNCHER}" "$file" 2>/dev/null; then
        WEB_APPS+=("$(basename "${file%.desktop}")")
        WEB_APP_PATHS+=("$file")
    fi
done < <(find "$DESKTOP_DIR" -name '*.desktop' -print0 2>/dev/null)

# The launcher matching a chosen name, or empty when nothing was indexed
# under it (an app removed between the scan and the pick, say).
path_for_web_app() {
    local wanted="$1" i
    for i in "${!WEB_APPS[@]}"; do
        if [[ ${WEB_APPS[$i]} == "$wanted" ]]; then
            printf '%s\n' "${WEB_APP_PATHS[$i]}"
            return 0
        fi
    done
}

if (( $# == 0 )); then
    if ((${#WEB_APPS[@]} == 0)); then
        echo "No web apps to remove."
        exit 1
    fi

    printf '\n\033[32mWeb apps installed:\033[0m\n\n'
    mapfile -t SORTED < <(printf '%s\n' "${WEB_APPS[@]}" | sort)
    i=1
    for app in "${SORTED[@]}"; do
        printf '  %2d) %s\n' "$i" "$app"
        ((i++))
    done
    printf '\n'

    while :; do
        read -r -p "Number (or name, q to cancel)> " answer || { echo; exit 1; }
        case $answer in
        '' | [Qq]) echo "Cancelled."; exit 0 ;;
        esac
        if [[ $answer =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#SORTED[@]})); then
            APP_NAME=${SORTED[answer - 1]}
            break
        fi
        # fall through: treat it as a literal name
        APP_NAME=$answer
        if [[ -n $(path_for_web_app "$APP_NAME") ]]; then break; fi
        printf '\033[31mNot one of the web apps listed.\033[0m\n' >&2
    done
else
    APP_NAME="$*"
fi

if [[ -z $APP_NAME ]]; then
    echo "You must select a web app to remove."
    exit 1
fi

icon_name=$(printf '%s\n' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')
desktop_file=$(path_for_web_app "$APP_NAME")
rm -f "${desktop_file:-$DESKTOP_DIR/$APP_NAME.desktop}"
rm -f "$ICON_DIR/$icon_name.png" "$ICON_DIR/$APP_NAME.png" "$OLD_ICON_DIR/$APP_NAME.png"

update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

printf '\033[32mRemoved %s\033[0m\n' "$APP_NAME"
