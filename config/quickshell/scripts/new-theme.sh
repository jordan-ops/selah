#!/usr/bin/env bash
# Scaffold a new selah theme: a colors.toml template with every key the
# pipeline reads, plus the derived quickshell files, ready to switch to.
#
# Usage: new-theme.sh <theme-name>
#   ...edit config/themes/<name>/colors.toml, then:
#        qs ipc call theme apply <theme-name>
#
# colors.toml is the single source: switch-theme.sh derives
# quickshell/colors.json + qtcolors.conf from it (cached), and
# global-theme.py derives kitty/GTK/foot/btop/chromium from it directly.
# An optional [qtc] block pins quickshell's typed roles where a derivation
# isn't what you want — see scripts/toml2colors.py.
set -euo pipefail

NAME="${1:-}"
if [ -z "$NAME" ]; then
    echo "Usage: new-theme.sh <theme-name>" >&2
    exit 1
fi
case "$NAME" in
    *[!A-Za-z0-9_-]*)
        echo "error: theme names may only contain letters, digits, '-' and '_'" >&2
        exit 1 ;;
esac

THEMES="$HOME/.config/themes"     # symlink -> ~/.dotfiles/config/themes
SRC="$THEMES/$NAME"
QS="$HOME/.config/quickshell"

if [ -e "$SRC" ]; then
    echo "error: theme already exists: $SRC" >&2
    exit 1
fi

mkdir -p "$SRC/quickshell"

# Template mirrors the key set of a shipped theme (red): the semantic
# names the converters' fallback chains read, the bright_* aliases
# global-theme.py's kitty pass indexes directly, and the ANSI color0-15
# slots for terminal themes. Values are a coherent dark green-accent
# starter palette — edit them.
cat > "$SRC/colors.toml" <<'EOF'
# selah theme — scaffolded by scripts/new-theme.sh; edit in place.
# Semantic names mirror Omarchy's theme color system; the color0-15 ANSI
# slots are kept for tools that still read them. Switch with:
#   qs ipc call theme apply <name>
mode = "dark"
accent = "#1db954"
background = "#121212"
bg = "#121212"
foreground = "#ffffff"
fg = "#ffffff"
bright_foreground = "#ffffff"
light_fg = "#ffffff"
muted = "#9e9e9e"
dark_bg = "#0e0e0e"
dark_fg = "#bfbfbf"
darker_bg = "#090909"
lighter_bg = "#2a2a2a"
selection = "#2a2a2a"
selection_background = "#2a2a2a"
selection_foreground = "#ffffff"
cursor = "#ffffff"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
orange = "#ff9e64"
brown = "#a0695a"
bright_red = "#ff8a9b"
bright_green = "#b9f27c"
bright_yellow = "#f0c674"
bright_blue = "#9db9f7"
bright_magenta = "#d0b5ff"
bright_cyan = "#a5e5ff"
color0 = "#121212"
color1 = "#f7768e"
color2 = "#9ece6a"
color3 = "#e0af68"
color4 = "#7aa2f7"
color5 = "#bb9af7"
color6 = "#7dcfff"
color7 = "#ffffff"
color8 = "#9e9e9e"
color9 = "#ff8a9b"
color10 = "#b9f27c"
color11 = "#f0c674"
color12 = "#9db9f7"
color13 = "#d0b5ff"
color14 = "#a5e5ff"
color15 = "#ffffff"

# Optional: pin quickshell's typed roles (services/Palette.qml) where the
# md3 derivation isn't what you want — everything not listed still derives.
# [qtc]
# textMuted = "#8a8a8a"
# surfaceAlt = "#2f2f2f"
EOF

# Derive the quickshell files now so the theme picker shows it and the
# first switch needs no extra passes (switch-theme.sh regenerates these
# itself once colors.toml is newer — this just front-runs the cache).
python3 "$QS/scripts/toml2colors.py"    "$SRC/colors.toml" "$SRC/quickshell/colors.json"
python3 "$QS/scripts/toml2qtpalette.py" "$SRC/colors.toml" "$SRC/quickshell/qtcolors.conf"

echo "created theme: $SRC"
echo "  1. edit colors.toml"
echo "  2. qs ipc call theme apply $NAME"
