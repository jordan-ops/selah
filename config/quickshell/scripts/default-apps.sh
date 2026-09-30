#!/usr/bin/env bash
# Default applications — one picker per ROLE, each role owning a family of
# document types (mime types). Everything applies through xdg-mime, so any
# program that honours the freedesktop defaults (file manager, browser,
# chat apps handing over links) opens documents with whatever the user
# picked on Settings ▸ Default apps. The terminal has no mime type: it
# lives in settings.json, and hypr's binds launch through this script
# (`launch terminal`) so Super+Return follows the picker too.
#
#   default-apps.sh list    <role>        candidates: "desktop-id<TAB>Name"
#   default-apps.sh current <role>        the default: "desktop-id<TAB>Name"
#   default-apps.sh set     <role> <id>   apply the choice
#   default-apps.sh seed                  fill every role that has NO default
#   default-apps.sh launch  <role>        exec the chosen app (hypr binds)
#
# Candidates are claim-based: an app only shows for a role if its .desktop
# file declares one of the role's mime types, so a pick can never be
# silently ignored at open time. `seed` walks a preference order ( what
# this desktop would pick for you) and takes the first installed claimer —
# and an EXISTING default is never touched: seeding only fills empty
# slots, so re-running install.sh can never stomp a user's own choice.
set -u

SETTINGS="$HOME/.local/state/quickshell/settings.json"

# -------- roles ------------------------------------------------------------

role_mimes() {            # ';' separated; terminal is empty on purpose
    case "$1" in
    browser)     echo "text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https" ;;
    editor)      echo "text/plain;text/markdown;text/csv;text/x-python;text/x-c;text/x-shellscript;application/json" ;;
    filemanager) echo "inode/directory" ;;
    image)       echo "image/png;image/jpeg;image/gif;image/webp;image/svg+xml;image/bmp;image/tiff;image/avif" ;;
    video)       echo "video/mp4;video/x-matroska;video/webm;video/x-msvideo;video/mpeg;video/quicktime" ;;
    audio)       echo "audio/mpeg;audio/mp4;audio/flac;audio/x-flac;audio/ogg;audio/wav;audio/x-wav;audio/aac;audio/x-m4a" ;;
    pdf)         echo "application/pdf" ;;
    archive)     echo "application/zip;application/x-tar;application/gzip;application/x-gzip;application/x-xz;application/x-bzip2;application/x-7z-compressed;application/x-rar" ;;
    office)      echo "application/vnd.oasis.opendocument.text;application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;text/rtf" ;;
    sheet)       echo "application/vnd.oasis.opendocument.spreadsheet;application/vnd.ms-excel;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ;;
    slide)       echo "application/vnd.oasis.opendocument.presentation;application/vnd.ms-powerpoint;application/vnd.openxmlformats-officedocument.presentationml.presentation" ;;
    terminal)    echo "" ;;
    *)           echo "" ;;
    esac
}

role_primary() { role_mimes "$1" | cut -d';' -f1; }

seed_order() {            # installed-and-claiming, best first
    case "$1" in
    browser)     echo "firefox.desktop org.mozilla.firefox.desktop chromium.desktop chromium-browser.desktop google-chrome.desktop brave-browser.desktop librewolf.desktop mullvad-browser.desktop" ;;
    terminal)    echo "foot.desktop org.codeberg.dnkl.foot.desktop kitty.desktop alacritty.desktop org.wezfurlong.wezterm.desktop com.mitchellh.ghostty.desktop org.gnome.terminal.desktop org.kde.konsole.desktop" ;;
    filemanager) echo "org.gnome.Nautilus.desktop nautilus.desktop thunar.desktop dolphin.desktop org.pcmanfm.PCManFM.desktop nemo.desktop" ;;
    editor)      echo "org.gnome.TextEditor.desktop gnome-text-editor.desktop org.gnome.gedit.desktop gedit.desktop code.desktop code-oss.desktop vscodium.desktop org.kde.kate.desktop kate.desktop mousepad.desktop org.xfce.mousepad.desktop" ;;
    image)       echo "org.gnome.Loupe.desktop loupe.desktop imv.desktop sxiv.desktop org.gnome.eog.desktop eog.desktop gthumb.desktop xviewer.desktop" ;;
    video)       echo "mpv.desktop celluloid.desktop org.gnome.Celluloid.desktop vlc.desktop org.gnome.Totem.desktop smplayer.desktop" ;;
    audio)       echo "mpv.desktop vlc.desktop amberol.desktop org.gnome.Lollypop.desktop audacious.desktop strawberry.desktop clementine.desktop org.gnome.Music.desktop" ;;
    pdf)         echo "zathura.desktop org.gnome.Evince.desktop evince.desktop org.kde.okular.desktop atril.desktop mupdf-gl.desktop firefox.desktop chromium.desktop google-chrome.desktop" ;;
    archive)     echo "org.gnome.FileRoller.desktop file-roller.desktop org.kde.ark.desktop engrampa.desktop xarchiver.desktop" ;;
    office)      echo "libreoffice-writer.desktop libreoffice.desktop org.onlyoffice.desktopeditors.desktop wps-office.desktop" ;;
    sheet)       echo "libreoffice-calc.desktop libreoffice.desktop org.onlyoffice.desktopeditors.desktop" ;;
    slide)       echo "libreoffice-impress.desktop libreoffice.desktop org.onlyoffice.desktopeditors.desktop" ;;
    *)           echo "" ;;
    esac
}

# -------- .desktop plumbing ------------------------------------------------

app_dirs() {
    printf '%s\n' \
        "$HOME/.local/share/applications" \
        "$HOME/.local/share/flatpak/exports/share/applications" \
        "/var/lib/flatpak/exports/share/applications" \
        "/usr/local/share/applications" \
        "/usr/share/applications"
}

desktop_file() {          # <id> -> path; user dirs win over system dirs
    local id="$1" d f
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        if [ -f "$d/$id" ]; then echo "$d/$id"; return 0; fi
        # -L: some distros ship .desktop as symlinks (libreoffice does)
        f=$(find -L "$d" -type f -name "$id" 2>/dev/null | head -1)
        [ -n "$f" ] && { echo "$f"; return 0; }
    done < <(app_dirs)
    return 1
}

all_desktops() {
    local d
    while IFS= read -r d; do
        [ -d "$d" ] && find -L "$d" -type f -name '*.desktop' 2>/dev/null
    done < <(app_dirs)
}

desk_name()  { sed -n 's/^Name=//p' "$1" | head -1; }
desk_mimes() { sed -n 's/^MimeType=//p' "$1" | head -1; }
desk_exec()  { sed -n 's/^Exec=//p' "$1" | head -1; }

claims() {                # <declared-mimes> <role> — exact token match
    local rms d m
    rms=$(printf '%s' "$(role_mimes "$2")" | tr ';' ' ')
    [ -n "$rms" ] || return 1
    for d in $(printf '%s' "$1" | tr ';' ' '); do
        for m in $rms; do [ "$d" = "$m" ] && return 0; done
    done
    return 1
}

# -------- settings.json key upsert (no qs / no python needed) --------------

set_setting() {           # <key> <string value> — value: [A-Za-z0-9._-]
    local key="$1" val="$2"
    mkdir -p "$(dirname "$SETTINGS")"
    [ -s "$SETTINGS" ] || printf '{}' > "$SETTINGS"
    if [ "$(cat "$SETTINGS")" = "{}" ]; then
        printf '{"%s":"%s"}' "$key" "$val" > "$SETTINGS"
    elif grep -qF "\"$key\"" "$SETTINGS"; then
        sed -i "s|\"$key\":\"[^\"]*\"|\"$key\":\"$val\"|" "$SETTINGS"
    else
        sed -i "s|}$|,\"$key\":\"$val\"}|" "$SETTINGS"
    fi
}

# -------- commands ---------------------------------------------------------

cmd_list() {
    local role="$1" id f seen=""
    if [ -z "$(role_mimes "$role")" ]; then
        # terminal: fixed menu of the usual suspects, installed only
        for id in $(seed_order "$role"); do
            f=$(desktop_file "$id") || continue
            printf '%s\t%s\n' "$id" "$(desk_name "$f")"
        done
        return 0
    fi
    while IFS= read -r f; do
        id=$(basename "$f")
        case ";$seen;" in *";$id;"*) continue ;; esac
        grep -q '^Hidden=true' "$f" && continue
        claims "$(desk_mimes "$f")" "$role" || continue
        seen="$seen;$id"
        printf '%s\t%s\n' "$id" "$(desk_name "$f")"
    done < <(all_desktops) | sort -t"$(printf '\t')" -k2
}

cmd_current() {
    local role="$1" id f
    # bare `current`: one line per role — the overview the README shows
    # (same order as the Settings page); roles with no pick are skipped
    if [ -z "$role" ]; then
        local r line
        for r in browser terminal filemanager editor image video audio pdf archive office sheet slide; do
            line=$(cmd_current "$r")
            [ -n "$line" ] && printf '%s\t%s\n' "$r" "$line"
        done
        return 0
    fi
    if [ "$role" = "terminal" ]; then
        id=$(sed -n 's/.*"defaults\.terminal"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                 "$SETTINGS" 2>/dev/null | head -1)
        if [ -z "$id" ]; then
            # no pick yet — first installed candidate is the fallback
            for id in $(seed_order terminal); do
                desktop_file "$id" >/dev/null 2>&1 && break
                id=""
            done
        fi
        [ -n "$id" ] || return 0
    else
        id=$(xdg-mime query default "$(role_primary "$role")" 2>/dev/null || true)
        [ -n "$id" ] || return 0
    fi
    if f=$(desktop_file "$id"); then
        printf '%s\t%s\n' "$id" "$(desk_name "$f")"
    else
        printf '%s\t%s\n' "$id" "$id"
    fi
}

cmd_set() {
    local role="$1" id="$2" m
    [ -n "$id" ] || return 0
    if [ "$role" = "terminal" ]; then
        set_setting "defaults.terminal" "$id"
        return 0
    fi
    for m in $(role_mimes "$role" | tr ';' ' '); do
        xdg-mime default "$id" "$m" 2>/dev/null || true
    done
    if [ "$role" = "browser" ]; then
        xdg-settings set default-web-browser "$id" 2>/dev/null || true
    fi
    return 0
}

cmd_seed() {
    local role id f cur n=0
    # terminal skipped on purpose: cmd_current's install-order fallback IS
    # the seed — the key only ever exists as an explicit user pick.
    for role in browser filemanager editor image video audio pdf archive office sheet slide; do
        cur=$(cmd_current "$role")
        [ -n "$cur" ] && continue            # already set — never stomp
        for id in $(seed_order "$role"); do
            f=$(desktop_file "$id") || continue
            grep -q '^Hidden=true' "$f" && continue
            claims "$(desk_mimes "$f")" "$role" || continue
            cmd_set "$role" "$id"
            n=$((n + 1))
            break
        done
    done
    if [ "$n" -gt 0 ]; then
        echo "seeded $n unset document-type default(s); the rest were already set"
    else
        echo "all document-type defaults already set"
    fi
    return 0
}

cmd_launch() {
    local role="$1" id f ex fw
    [ -n "$role" ] || return 1   # bare `launch` is a usage error, never a pick
    id=$(cmd_current "$role" | cut -f1)
    if [ -n "$id" ] && f=$(desktop_file "$id"); then
        ex=$(desk_exec "$f" | sed 's/ %[fFuUdDnNickvm]//g')
        fw=${ex%% *}
        # only replace ourselves when the binary actually resolves — a
        # stale default (app uninstalled) must reach the fallback below
        if [ -n "$fw" ] && command -v "$fw" >/dev/null 2>&1; then
            exec sh -c "$ex"
        fi
    fi
    # nothing resolvable — fall back to what the package list guarantees
    case "$role" in
    terminal)    exec foot ;;
    filemanager) exec nautilus ;;
    browser)     exec chromium ;;
    esac
    return 1
}

# -------- entry ------------------------------------------------------------

case "${1:-}" in
list)    cmd_list "${2:-}" ;;
current) cmd_current "${2:-}" ;;
set)     cmd_set "${2:-}" "${3:-}" ;;
seed)    cmd_seed ;;
launch)  [ -n "${2:-}" ] || { echo "usage: default-apps.sh launch <role>" >&2; exit 2; }
         cmd_launch "$2" ;;
*)       echo "usage: default-apps.sh list|current|set|seed|launch <role> [desktop-id]" >&2
         exit 2 ;;
esac
exit 0
