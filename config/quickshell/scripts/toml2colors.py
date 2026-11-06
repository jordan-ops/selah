#!/usr/bin/env python3
"""Derive quickshell's colors.json from a theme's colors.toml.

Selah themes are flat palettes (background / foreground / accent / muted /
dark_background / lighter_background / selection / red ...), while QML wants
semantic, quirk-free names. Two blocks are emitted:

  md3  — the historical Material-3 key names services/Colors.qml has always
         read (and modules/ThemePicker.qml reads for swatches). Unchanged
         derivation, so every existing theme keeps producing the same file.
  qtc  — the unified palette block Palette.qml reads: camelCase semantic
         roles (background/surface/surfaceAlt/accent/text/textMuted/critical/
         low). Values come from an optional [qtc] table in colors.toml when
         the theme spells them out, otherwise they derive from the same flat
         keys as md3 — so themes written before qtc behave identically.

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

    # qtc mirrors md3's derivations under QML-semantic names, then lets an
    # explicit [qtc] table override any of them (a theme can pin textMuted
    # without disturbing the flat `muted` key other apps read).
    qtc = {
        "background": md3["background"],
        "surface": md3["surface_variant"],
        "surfaceAlt": md3["secondary_container"],
        "accent": md3["primary"],
        "text": md3["on_background"],
        "textMuted": md3["on_surface_variant"],
        "critical": md3["error"],
        "low": md3["outline"],
    }
    explicit = colors.get("qtc")
    if isinstance(explicit, dict):
        for key, value in explicit.items():
            if isinstance(value, str) and value:
                qtc[key] = value

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    tmp.write_text(json.dumps({"md3": md3, "qtc": qtc}, indent=2) + "\n")
    tmp.replace(dst)


if __name__ == "__main__":
    main()
