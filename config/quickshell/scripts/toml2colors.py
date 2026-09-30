#!/usr/bin/env python3
"""Derive quickshell's colors.json (md3 keys) from an omarchy colors.toml.

omarchy themes are flat palettes (background / foreground / accent / muted /
dark_background / lighter_background / selection / red ...), while
services/Colors.qml reads md3.background, md3.surface_variant,
md3.secondary_container, md3.primary, md3.on_background,
md3.on_surface_variant, md3.error, md3.outline.

This maps one to the other with fallback chains so themes missing the
optional omarchy keys still produce a complete file.

Usage: toml2colors.py <colors.toml> <colors.json>
"""
import json
import sys
import tomllib
from pathlib import Path


def pick(colors, *keys, default):
    for key in keys:
        value = colors.get(key)
        if isinstance(value, str) and value:
            return value
    return default


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: toml2colors.py <colors.toml> <colors.json>")

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])

    with src.open("rb") as f:
        colors = tomllib.load(f)

    background = pick(colors, "background", default="#282828")
    foreground = pick(colors, "foreground", default="#ffffff")

    md3 = {
        # base surfaces
        "background": background,
        "surface_variant": pick(colors, "dark_background", default=background),
        "secondary_container": pick(colors, "lighter_background", "selection",
                                    default=background),
        # accent + text
        "primary": pick(colors, "accent", default="#1db954"),
        "on_background": foreground,
        "on_surface_variant": pick(colors, "muted", "dark_foreground",
                                   default=foreground),
        # alerts + borders
        "error": pick(colors, "red", default="#e74c3c"),
        "outline": pick(colors, "selection", "muted", default="#555555"),
    }

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    tmp.write_text(json.dumps({"md3": md3}, indent=2) + "\n")
    tmp.replace(dst)


if __name__ == "__main__":
    main()
