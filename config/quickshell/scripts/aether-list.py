#!/usr/bin/env python3
"""One JSON document for the picker: the local library plus wallpapers grouped by theme.

Three sources are merged here rather than in QML, because grouping needs
symlink resolution (Qt has no realpath) and the theme directories are only
reachable by scanning them directly:

  1. `aether --list-wallpapers --json --with-previews` — aether's own recursive
     scan of ~/Wallpapers. Its previewPath values point at cached 800 px PNGs in
     ~/.cache/aether/thumbnails, so the grid never decodes a 6 K wallpaper.
     Warm cost ~70 ms.
  2. ~/.config/themes/<name>/backgrounds/* — every theme's own copies. One file
     can live only in a theme (aether-sword's default.png is not linked into
     ~/Wallpapers), so a group built from the listing alone would be incomplete.
  3. ~/Wallpapers + aether's download dir, filtered down to files that do NOT
     belong to a theme.

The split is the whole point of the Themes tab: theme wallpapers are listed
grouped, and `local` holds only standalone files, so nothing is scattered.

Output: {"local": [...], "themes": [...], "wallpapers": N, "error": null}
Item shape (identical in both lists, so the grid never cares which it draws):
  {path, name, previewPath, size, theme}      theme = "" for standalone files
Group shape:
  {name, dir, count, cover, wallpapers: [item]}

Usage: aether-list.py [--json]
"""
import json
import os
import pathlib
import subprocess
import sys

HOME = pathlib.Path.home()
THEMES_DIR = HOME / ".config" / "themes"
# aether downloads full-size wallhaven images here; they are local files like
# any other once they exist, so they belong in the standalone list.
EXTRA_DIRS = [HOME / ".local" / "share" / "aether" / "wallpapers"]
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}


def aether_scan():
    """aether's listing, previews included. Degrades to a bare scan on error."""
    try:
        proc = subprocess.run(
            ["aether", "--list-wallpapers", "--json", "--with-previews"],
            capture_output=True, text=True, timeout=90,
        )
        data = json.loads(proc.stdout)
        return [w for w in data.get("wallpapers", []) if w.get("path")]
    except Exception as exc:                                  # noqa: BLE001
        print(f"aether-list: aether scan failed: {exc}", file=sys.stderr)
        return _bare_scan()


def _bare_scan():
    """No previews, no colour — still a usable grid if `aether` is missing."""
    root = HOME / "Wallpapers"
    if not root.is_dir():
        return []
    out = []
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.suffix.lower() in IMAGE_EXT:
            out.append({"path": str(p), "name": p.name, "size": p.stat().st_size,
                        "modTime": 0, "previewPath": ""})
    return out


def theme_groups(owners, preview_of):
    """{theme name -> [item]} for every image living under ~/.config/themes."""
    groups = {}
    if not THEMES_DIR.is_dir():
        return groups
    for tdir in sorted(THEMES_DIR.iterdir()):
        if not tdir.is_dir():
            continue
        # switch-theme.sh accepts either name; aether writes backgrounds/.
        bg = tdir / "backgrounds"
        if not bg.is_dir():
            bg = tdir / "wallpapers"
        if not bg.is_dir():
            continue
        items = []
        for f in sorted(bg.iterdir()):
            if not f.is_file() or f.suffix.lower() not in IMAGE_EXT:
                continue
            real = str(f.resolve())
            # Reuse the listing's cached preview when this very file is also in
            # ~/Wallpapers (it will be, for every seeded symlink).
            info = preview_of.get(real, {})
            items.append({
                "path": str(f),
                "name": f.name,
                "previewPath": info.get("previewPath", ""),
                "size": info.get("size", f.stat().st_size),
                "modTime": info.get("modTime", 0),
                "theme": tdir.name,
            })
        if items:
            groups[tdir.name] = items
    return groups


def main():
    listing = aether_scan()

    preview_of = {}
    for w in listing:
        try:
            preview_of.setdefault(str(pathlib.Path(w["path"]).resolve()), w)
        except OSError:
            pass

    groups = theme_groups(None, preview_of)

    # realpath -> owning theme, for badging the standalone list.
    owner_of = {}
    for name, items in groups.items():
        for it in items:
            owner_of[str(pathlib.Path(it["path"]).resolve())] = name

    local = []
    seen = set()
    for w in listing:
        try:
            real = str(pathlib.Path(w["path"]).resolve())
        except OSError:
            real = w["path"]
        if real in seen:
            continue
        seen.add(real)
        if real in owner_of:
            continue                      # it is a theme's wallpaper: grouped, not scattered
        local.append({
            "path": w["path"],
            "name": pathlib.Path(w["path"]).name,
            "previewPath": w.get("previewPath", ""),
            "size": w.get("size", 0),
            "modTime": w.get("modTime", 0),
            "theme": "",
        })

    for extra in EXTRA_DIRS:
        if not extra.is_dir():
            continue
        for f in sorted(extra.iterdir()):
            if not f.is_file() or f.suffix.lower() not in IMAGE_EXT:
                continue
            real = str(f.resolve())
            if real in seen or real in owner_of:
                continue
            seen.add(real)
            local.append({"path": str(f), "name": f.name, "previewPath": "",
                          "size": f.stat().st_size, "modTime": 0, "theme": ""})

    # Most wallpapers first: a theme with one image should not sit above a
    # nine-image one when you are looking for variety.
    themes = sorted(
        ({"name": n,
          "dir": str(THEMES_DIR / n),
          "count": len(items),
          "cover": items[0]["previewPath"] or items[0]["path"],
          "wallpapers": items}
         for n, items in groups.items()),
        key=lambda g: (-g["count"], g["name"].lower()),
    )

    doc = {"local": local, "themes": themes,
           "wallpapers": sum(g["count"] for g in themes) + len(local),
           "error": None}
    if "--bare" in sys.argv:
        doc = {"local": local, "themes": [], "wallpapers": len(local), "error": None}
    json.dump(doc, sys.stdout)
    print()


if __name__ == "__main__":
    main()
