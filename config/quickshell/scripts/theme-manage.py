#!/usr/bin/env python3
"""Delete or rename a theme directory — the picker's "Rename" / "Delete".

usage: theme-manage.py delete <name>
       theme-manage.py rename <old> <new>

Prints exactly one JSON object on stdout:
    {"ok": true,  "name": "<name after the op>", "applied": <bool>}
    {"ok": false, "error": "<reason>"}

Guards, in order:
  * the name has to look like a theme slug — no path separators, no "..",
    no leading dot — before it is ever joined onto ~/.config/themes;
  * the join has to land on a direct child of that directory;
  * the source has to exist;
  * deleting the theme the desktop is currently wearing is refused, because
    btop, hyprland, kitty and the shell all still point at it.

Deleting only removes the theme directory plus its two regenerable derived
files (the shell thumbnail and btop's per-theme file). Renaming the active
theme re-runs switch-theme.sh under the new name, since that is what rewrites
current-theme, btop's color_theme and the generated copies consumers read.
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
BASE = HOME / ".config" / "themes"
# NOTE: this is `.local/state/quickshell`, not `.local/quickshell` — with the
# `state` component missing, current-theme silently never reads and the
# "you cannot delete the active theme" guard below never fires.
STATE = HOME / ".local" / "state" / "quickshell"
THUMBS = STATE / "generated" / "thumbnails"
BTOP = HOME / ".config" / "btop" / "themes"
SWITCH = HOME / ".config" / "quickshell" / "scripts" / "switch-theme.sh"

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def say(doc):
    print(json.dumps(doc))
    raise SystemExit(0)


def fail(msg):
    say({"ok": False, "error": msg})


def resolve(name, what):
    if not isinstance(name, str) or ".." in name or not NAME_RE.match(name):
        fail("that does not look like a theme name")
    target = BASE / name
    try:
        if target.parent.resolve() != BASE.resolve():
            fail("refusing to touch anything outside ~/.config/themes")
    except OSError:
        fail("could not resolve " + name)
    return target


def active_theme():
    try:
        return (STATE / "current-theme").read_text().strip()
    except OSError:
        return ""


def drop_derived(name):
    """Both files are regenerable, and leaving them behind keeps a deleted
    theme visible in btop's theme list and the shell's thumbnail cache."""
    for victim in (
        THUMBS / (name + ".png"),
        BTOP / ("quickshell-" + name + ".theme"),
    ):
        try:
            victim.unlink()
        except OSError:
            pass


def do_delete(name):
    target = resolve(name, "deletion")
    if target.is_symlink():
        target.unlink()
    elif target.is_dir():
        if active_theme() == name:
            fail("that theme is active — switch to another one first")
        shutil.rmtree(target)
    else:
        fail("no theme called " + name)
    drop_derived(name)
    say({"ok": True, "name": name, "applied": False})


def do_rename(old, new):
    src = resolve(old, "rename")
    dst = resolve(new, "rename")
    if not src.exists() and not src.is_symlink():
        fail("no theme called " + old)
    if old == new:
        say({"ok": True, "name": old, "applied": False})
    if dst.exists() or dst.is_symlink():
        fail("a theme called " + new + " already exists")

    was_active = active_theme() == old
    src.rename(dst)

    old_btop = BTOP / ("quickshell-" + old + ".theme")
    new_btop = BTOP / ("quickshell-" + new + ".theme")
    if old_btop.is_file() and not (new_btop.exists() or new_btop.is_symlink()):
        try:
            old_btop.rename(new_btop)
        except OSError:
            pass

    # Same story for the shell's cached thumbnail: without this the old name
    # keeps a stray PNG forever and the new name never gets one.
    old_png = THUMBS / (old + ".png")
    new_png = THUMBS / (new + ".png")
    if old_png.is_file() and not (new_png.exists() or new_png.is_symlink()):
        try:
            old_png.rename(new_png)
        except OSError:
            pass

    # The pointer goes first: a dangling current-theme would be worse than a
    # stale btop entry if the retint below falls over halfway.
    applied = False
    if was_active:
        try:
            (STATE / "current-theme").write_text(new + "\n")
            applied = subprocess.run(
                ["bash", str(SWITCH), new],
                capture_output=True,
                timeout=120,
            ).returncode == 0
        except Exception:
            applied = False
    say({"ok": True, "name": new, "applied": applied})


def main(argv):
    if len(argv) == 2 and argv[0] == "delete":
        do_delete(argv[1])
    if len(argv) == 3 and argv[0] == "rename":
        do_rename(argv[1], argv[2])
    fail("usage: theme-manage.py delete <name> | rename <old> <new>")


if __name__ == "__main__":
    main(sys.argv[1:])
