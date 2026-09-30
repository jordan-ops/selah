#!/bin/bash

# selah-remove-app — uninstall from the launcher (Delete key → confirm → go).
#
#   remove-app.sh <desktop-id>
#
# The launcher only knows quickshell's desktop-entry id ("Youtube",
# "foot"), so resolve id -> file across the XDG search order (user dir
# first — exactly how quickshell ranks them).
#
# Two branches, decided by WHERE that file lives:
#
#   * ~/.local/share/applications — a web app or hand-placed launcher:
#     delete the .desktop file and the icon the installer put in hicolor,
#     refresh the database. Silent when headless: quickshell detaches us
#     and its own list refreshes when the file goes away.
#
#   * anywhere else — a real package. sudo needs a TTY and the user must
#     SEE what pacman is about to remove, so this runs inside foot, titled
#     "Uninstall <app>" (rules.lua floats that title). No TTY because
#     quickshell spawned us? Reopen ourselves under foot first — same
#     pattern install-app.sh uses.
#
# No `set -e`: under foot an abort would close the window before the
# error could be read. Every step reports and carries on.

id="${1:-}"
if [ -z "$id" ]; then
    echo "Usage: remove-app.sh <desktop-id>" >&2
    exit 1
fi
id="${id%.desktop}"

USER_DIR="$HOME/.local/share/applications"
file=""
for dir in "$USER_DIR" /usr/local/share/applications /usr/share/applications; do
    if [ -f "$dir/$id.desktop" ]; then
        file="$dir/$id.desktop"
        break
    fi
done

if [ -z "$file" ]; then
    echo "No desktop entry '$id' in the search path." >&2
    exit 1
fi

name=$(sed -n 's/^Name=//p' "$file" | head -n1)
name=${name:-$id}

# Package names reach a shell command line. Rather than escape them for
# every possible metacharacter, reject anything that is not a legal pacman
# name — same rule install-app.sh enforces.
validate_packages() {
    local p
    for p in $1; do
        if [[ ! $p =~ ^[a-zA-Z0-9@._+-]+$ ]]; then
            printf 'Not a valid package name: %s\n' "$p" >&2
            return 1
        fi
    done
    return 0
}

case "$file" in
"$USER_DIR"/*)
    # ---- web app / user launcher: delete the file itself -------------
    if [ -t 0 ]; then
        printf '\033[32mDelete web app launcher\033[0m\n\n  %s\n  %s\n\n' "$name" "$file"
    fi

    icon=$(sed -n 's/^Icon=//p' "$file" | head -n1)
    rm -f "$file"
    if [ -n "$icon" ]; then
        case $icon in
        /* | ./* | "~"*)
            # a path rather than a theme name
            rm -f "${icon/#\~/$HOME}"
            ;;
        *)
            rm -f "$USER_DIR/icons/$icon.png" \
                "$HOME/.local/share/applications/icons/$icon.png"
            # every installed size of this name (png/svg/stray originals);
            # unmatched globs stay literal and rm -f takes them quietly
            rm -f "$HOME"/.local/share/icons/hicolor/*/apps/"$icon".*
            ;;
        esac
    fi
    update-desktop-database "$USER_DIR" &>/dev/null || true

    if [ -t 0 ]; then
        printf '\033[32mRemoved %s\033[0m\n\nPress Enter to close.' "$name"
        read -r _ || true
    fi
    ;;

*)
    # ---- system package: hand it to pacman in a real terminal --------
    if [ ! -t 0 ]; then
        # headless (quickshell) — foot -T supplies the title the Hyprland
        # rule matches to float+center this window; -w roomier than the
        # 80x24 default so the pacman prompt/list isn't cramped
        exec foot -T "Uninstall $name" -w 860x580 -e "$0" "$id"
    fi

    printf '\033[1mUninstall %s\033[0m\n\n' "$name"

    # Exec -> binary -> owning package. Field-code tokens (%U, %f, ...) and
    # `env VAR=x` prefixes are skipped so we resolve the app itself.
    exec_line=$(grep -m1 '^Exec=' "$file" | cut -d= -f2-)
    set -- $exec_line
    bin=""
    while [ $# -gt 0 ]; do
        case $1 in
        %*) shift ;;
        *=*) shift ;;
        env) shift ;;
        *) bin=$1; break ;;
        esac
    done

    pkg=""
    if [ -n "$bin" ] && [ "${bin##*/}" != flatpak ] && [ "${bin##*/}" != snap ]; then
        bin_path=$(command -v "$bin" 2>/dev/null)
        if [ -z "$bin_path" ] && [ -x "$bin" ]; then
            bin_path=$bin
        fi
        if [ -n "$bin_path" ]; then
            pkg=$(pacman -Qo "$bin_path" 2>/dev/null | awk '{print $5; exit}')
        fi
    fi

    if [ -z "$pkg" ]; then
        printf 'Could not detect a pacman package automatically.\n' >&2
        if [ "${bin##*/}" = flatpak ] || [ "${bin##*/}" = snap ]; then
            printf '  (%s apps are not pacman packages — remove with flatpak/snap itself.)\n' "$bin" >&2
        elif [ -n "$bin" ]; then
            printf '  Exec starts with: %s\n' "$bin" >&2
        fi
        while [ -z "$pkg" ]; do
            read -r -p "Package(s) to remove> " pkg || exit 1
        done
    fi

    validate_packages "$pkg" || exit 1

    printf 'Launcher: %s\n' "$file"
    printf 'Removing  \033[1m%s\033[0m\n\n' "$pkg"
    printf '\033[2mPassword prompt below. Closing this window while it waits\n'
    printf 'counts as a failed login, and 3 of those lock your account.\n'
    printf 'If that happens, run:  faillock --user %s --reset\033[0m\n\n' "$USER"
    if sudo pacman -Rns -- $pkg; then
        printf '\n\033[32mRemoved %s.\033[0m\n' "$name"
    else
        printf '\n\033[31mRemoval failed or was cancelled.\033[0m\n'
    fi
    printf '\nPress Enter to close.'
    read -r _ || true
    ;;
esac
