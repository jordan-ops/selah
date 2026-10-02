#!/usr/bin/env python3
"""Derive a qt5ct/qt6ct color scheme from an omarchy colors.toml.

Both ct utilities read one palette format: [ColorScheme] with
active/inactive/disabled_colors, each a comma-separated list of 21
#aarrggbb values indexed by QPalette role in the palette editors'
order (WindowText, Button, Light, MidLight, Dark, Mid, Text,
BrightText, ButtonText, Base, Window, Shadow, Highlight,
HighlightedText, Link, LinkVisited, AlternateBase, NoRole, ToolTipBase,
ToolTipText, PlaceholderText). qt6ct's loader accepts that 21-entry
list and derives Accent from Highlight itself, while qt5ct insists on
exactly NColorRoles (21) entries — so one file serves both and
switch-theme.sh symlinks the qt5ct copy to the qt6ct one.

Roles come from the flat omarchy palette with the same fallback chains
as toml2colors.py, so themes missing optional keys still yield a
complete scheme. mode splits the surface geometry: in dark themes
inputs/buttons sit *lighter* than the window, in light themes they sit
*darker* (the shipped qt6ct schemes follow the same rule).

switch-theme.sh derives this next to colors.json (per-theme cache) and
ships it to ~/.config/qt6ct/colors/selah.conf. Qt reads the palette at
startup, so already-running apps keep the old scheme until restarted.

Usage: toml2qtpalette.py <colors.toml> <selah.conf>
"""
import sys
import tomllib
from pathlib import Path

# the four text roles qt6ct's "build disabled palette" greys out
DISABLED_TEXT_ROLES = (0, 6, 8, 13)


def pick(colors, *keys, default):
    for key in keys:
        value = colors.get(key)
        if isinstance(value, str) and value:
            return value
    return default


def rgb(value):
    if isinstance(value, tuple):
        return value
    value = value.lstrip("#")
    if len(value) == 3:
        value = "".join(ch * 2 for ch in value)
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(first, second, amount):
    a, b = rgb(first), rgb(second)
    return tuple(round(x + (y - x) * amount) for x, y in zip(a, b))


def lighten(color, amount):
    return mix(color, "#ffffff", amount)


def darken(color, amount):
    return mix(color, "#000000", amount)


def on(color):
    """Readable text colour for a given background."""
    r, g, b = rgb(color)
    luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    return rgb("#1a1a1a") if luminance > 0.6 else rgb("#ffffff")


def line(colors):
    return ", ".join("#ff%02x%02x%02x" % c for c in colors)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: toml2qtpalette.py <colors.toml> <selah.conf>")

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])

    with src.open("rb") as f:
        colors = tomllib.load(f)

    light = pick(colors, "mode", default="dark") == "light"
    window = rgb(pick(colors, "background", "bg", default="#282828"))
    foreground = rgb(pick(colors, "foreground", "fg", default="#ffffff"))
    muted = rgb(pick(colors, "muted", default="#ffffff"))
    accent = rgb(pick(colors, "accent", default="#1db954"))
    # omarchy's surface keys: lighter_background/dark_background are the
    # canonical spelling, *_bg the aether alias — the theme set uses both.
    lighter = rgb(pick(colors, "lighter_background", "lighter_bg",
                       default=lighten(window, 0.09) if not light else darken(window, 0.07)))
    darker = rgb(pick(colors, "dark_background", "dark_bg",
                      default=darken(window, 0.05)))
    darkest = rgb(pick(colors, "darker_bg", "darker_background",
                       default=darken(window, 0.50)))

    if light:
        button = lighter
        base = darken(button, 0.07)
        altbase = mix(window, base, 0.5)
        shadow = darken(window, 0.45)
    else:
        button = lighter
        base = lighter
        altbase = darker
        shadow = darkest

    roles = [
        foreground,                    # WindowText
        button,                        # Button
        lighten(button, 0.30),         # Light
        lighten(button, 0.15),         # MidLight
        darken(button, 0.22),          # Dark
        darken(button, 0.11),          # Mid
        foreground,                    # Text
        foreground,                    # BrightText
        foreground,                    # ButtonText
        base,                          # Base
        window,                        # Window
        shadow,                        # Shadow
        accent,                        # Highlight
        on(accent),                    # HighlightedText
        accent,                        # Link
        mix(accent, foreground, 0.35),  # LinkVisited
        altbase,                       # AlternateBase
        foreground,                    # NoRole ("Default")
        base,                          # ToolTipBase
        foreground,                    # ToolTipText
        muted,                         # PlaceholderText
    ]

    disabled = list(roles)
    for i in DISABLED_TEXT_ROLES:
        disabled[i] = rgb("#808080")

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    tmp.write_text(
        "[ColorScheme]\n"
        f"active_colors={line(roles)}\n"
        f"disabled_colors={line(disabled)}\n"
        f"inactive_colors={line(roles)}\n"
    )
    tmp.replace(dst)


if __name__ == "__main__":
    main()
