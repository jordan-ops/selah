#!/usr/bin/env bash
set -e

THEME="$1"
SRC="$HOME/.config/themes/$THEME"

if [ -z "$THEME" ] || [ ! -d "$SRC" ]; then
    echo "Usage: switch-theme.sh <theme-name>"
    exit 1
fi

mkdir -p "$HOME/.local/state/quickshell"
printf '%s\n' "$THEME" > "$HOME/.local/state/quickshell/current-theme"

# omarchy themes ship colors.toml, not ready-made derived configs —
# derive quickshell's colors.json (the md3 keys services/Colors.qml
# reads) and qt5ct/qt6ct's selah scheme (toml2qtpalette.py) before the
# copy loop below ships them. Cached per theme: only regenerate when
# colors.toml is newer than a derived file or the file is missing, so
# re-switching a theme skips the python passes entirely (omarchy caches
# everything it can between switches).
if [ -f "$SRC/colors.toml" ] && {
    [ ! -f "$SRC/quickshell/colors.json" ] || [ "$SRC/colors.toml" -nt "$SRC/quickshell/colors.json" ] ||
    [ ! -f "$SRC/quickshell/qtcolors.conf" ]
}; then
    mkdir -p "$SRC/quickshell"
    python3 "$HOME/.config/quickshell/scripts/toml2colors.py" \
        "$SRC/colors.toml" "$SRC/quickshell/colors.json" || true
    python3 "$HOME/.config/quickshell/scripts/toml2qtpalette.py" \
        "$SRC/colors.toml" "$SRC/quickshell/qtcolors.conf" || true
fi

# source subfolder -> real destination file
declare -A TARGETS=(
    [quickshell/colors.json]="$HOME/.local/state/quickshell/generated/colors.json"
    [quickshell/qtcolors.conf]="$HOME/.config/qt6ct/colors/selah.conf"
    [kitty/theme.conf]="$HOME/.config/kitty/current-theme.conf"
    [GTK/theme.css]="$HOME/.config/gtk-3.0/theme.css"
    [hypr/colors.lua]="$HOME/.config/hypr/colors.lua"
)

for src_rel in "${!TARGETS[@]}"; do
    dest="${TARGETS[$src_rel]}"
    if [ -f "$SRC/$src_rel" ]; then
        mkdir -p "$(dirname "$dest")"
        if [ "$src_rel" = "quickshell/colors.json" ]; then
            # in-place write — Colors.qml's FileView holds an inotify watch
            # on this path; an atomic mv swaps the inode so the watch never
            # fires and the shell keeps rendering its old palette.
            cat "$SRC/$src_rel" > "$dest"
        else
            cp "$SRC/$src_rel" "$dest.tmp"
            mv "$dest.tmp" "$dest"
        fi
    fi
done

if [ -f "$SRC/GTK/theme.css" ]; then
    mkdir -p "$HOME/.config/gtk-4.0"
    ln -sf "$HOME/.config/gtk-3.0/theme.css" "$HOME/.config/gtk-4.0/theme.css"
fi

# qt5ct reads the same 21-slot scheme as qt6ct (its loader wants exactly
# NColorRoles entries, qt6ct derives Accent from Highlight itself), so
# share one file instead of keeping two copies in sync — same trick as
# gtk-4.0/theme.css above.
if [ -f "$SRC/quickshell/qtcolors.conf" ]; then
    mkdir -p "$HOME/.config/qt5ct/colors"
    ln -sf "$HOME/.config/qt6ct/colors/selah.conf" "$HOME/.config/qt5ct/colors/selah.conf"
fi

# point quickshell's background window at this theme's default wallpaper —
# quickshell renders the wallpaper itself now (Background.qml), so this is
# just a state-file write; Wallpapers.qml's FileView picks it up live and
# crossfades. A theme without images keeps whatever is already set. Runs
# BEFORE the app retint so the wallpaper transition starts immediately.
WALLPAPER_DIR=""
if [ -d "$SRC/backgrounds" ]; then
    WALLPAPER_DIR="$SRC/backgrounds"
elif [ -d "$SRC/wallpapers" ]; then
    WALLPAPER_DIR="$SRC/wallpapers"
fi
if [ -n "$WALLPAPER_DIR" ]; then
    DEFAULT=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f -iname "default.*" | head -n1)
    if [ -z "$DEFAULT" ]; then
        DEFAULT=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
            | sort | head -n1)
    fi
    if [ -n "$DEFAULT" ] \
        && [ "$(cat "$HOME/.local/state/quickshell/current-wallpaper" 2>/dev/null)" != "$DEFAULT" ]; then
        # skip the write when the state already points at this exact file:
        # rewriting an identical path still fires the FileView inotify and
        # restarts the crossfade for nothing (part of the "switch feels
        # slow sometimes" variance). Different path -> write as before.
        printf '%s' "$DEFAULT" > "$HOME/.local/state/quickshell/current-wallpaper"
    fi
fi

# The instant-feedback half is already done by here: colors.json recolored
# the shell in the copy loop and the wallpaper write kicked off its
# crossfade. Now retint the running apps. Omarchy's run_parallel lesson:
# kitty, hyprland and the global gsettings/foot/editor pass touch different
# things, so run them TOGETHER instead of stacking their latencies (~110ms
# + 16ms + 640ms serial -> one ~640ms wave). `wait` keeps quickshell's
# one-switch-at-a-time queue honest: the next apply starts only after every
# retint from this one has finished, so no two passes race on the same
# configs.
if command -v kitty >/dev/null 2>&1 && pgrep -x kitty >/dev/null 2>&1; then
    # -k 1: TERM at 3s, then KILL at 4s. Hard-fact: without a running kitty
    # this kitten can get SIGTTIN-stopped on the session's controlling tty,
    # and it CATCHES SIGTERM — so plain `timeout 3` sent a TERM nobody would
    # ever act on and then waited forever, wedging quickshell's apply queue
    # (theme switches silently no-op'd behind it). SIGKILL cannot be caught.
    timeout -k 1 3 kitty @ set-colors --all "$HOME/.config/kitty/current-theme.conf" >/dev/null 2>&1 || true &
fi
if command -v hyprctl > /dev/null 2>&1; then
    timeout -k 1 5 hyprctl reload > /dev/null 2>&1 || true &
fi

# cliamp (retro terminal player) keeps its palette in config.toml rather
# than a shared theme file, so push the shell theme in BY NAME — cliamp
# ships 16 of ours (tokyo-night, miasma, gruvbox, nord…). `cliamp theme
# <name>` writes the file and pokes a running instance over its socket, so
# an open TUI recolors without restarting. A theme cliamp has never heard
# of is left alone instead of failing the switch.
if command -v cliamp >/dev/null 2>&1 \
    && cliamp theme list 2>/dev/null | tr -d ' ' | grep -qx "$THEME"; then
    timeout -k 1 3 cliamp theme "$THEME" >/dev/null 2>&1 || true
fi

# global theming — omarchy-style: gsettings/GTK, foot (ini + live OSC),
# kitty, chromium policy. Everything user-session runs inline; the /etc
# policy push degrades gracefully until one-time-root-setup.sh has run.
# Hard `timeout 10`: a wedged D-Bus call or a foot tty whose buffer is
# full used to be able to hold this job (and quickshell's one-switch-at-
# a-time queue behind it) indefinitely — that's the "sometimes the theme
# switch takes forever" case. Bounded now: worst case costs 10s, never a
# stuck queue.
timeout -k 1 10 python3 "$HOME/.config/quickshell/scripts/global-theme.py" "$SRC" || true &

# greeter sync — push the current wallpaper + palette into the staged SDDM
# theme so the login screen matches the shell theme (self-contained: the
# staged copy refreshes always, the installed copy only when the one-time
# sudo setup has put the root helper in place).
timeout -k 1 8 "$HOME/.config/quickshell/scripts/selah-sddm.sh" sync >/dev/null 2>&1 || true &

wait || true
