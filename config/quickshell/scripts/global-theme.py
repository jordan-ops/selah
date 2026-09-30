#!/usr/bin/env python3
"""Global theming — omarchy-style app coordination for this quickshell setup.

Ports the user-session half of omarchy's post-theme hooks to switch-theme.sh:

  * omarchy-theme-set-gnome   -> gsettings color-scheme / gtk-theme / icon-theme
  * (nwg-look equivalent)     -> gtk-3.0 + gtk-4.0 settings.ini
  * omarchy-theme-set-foot    -> generated foot.ini + live OSC to running footes
  * kitty.conf.tpl            -> generated current-theme.conf (+ include shim)
  * omarchy-theme-set-browser -> staged browser-color.json + best-effort push
                                 to /etc/chromium/policies/managed/color.json

Everything user-session runs directly; the /etc policy write tries a direct
write, then `sudo -n` (the passwordless helper one-time-root-setup.sh installs),
then gives up silently — the staged JSON stays current so the policy catches up
on the next run after setup.

Usage: global-theme.py <theme-dir> [--dry-run]
"""

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

HOME = pathlib.Path.home()
STATE = HOME / ".local/state/quickshell/generated"
POLICY_DEST = pathlib.Path("/etc/chromium/policies/managed/color.json")
BROWSER_HELPER = "/usr/local/bin/set-browser-color"

DRY = "--dry-run" in sys.argv


# ---------------------------------------------------------------- palette ---
# Port of omarchy-theme-color's resolution cascade: semantic names are
# canonical, ANSI colorN aliases fill gaps, brights default to a 20% white
# mix, mode falls back to background luminance (same >382 sum threshold).

def mix(start: str, end: str, amount: float) -> str:
    s = start.lstrip("#")
    e = end.lstrip("#")
    out = []
    for i in (0, 2, 4):
        a = int(s[i:i + 2], 16)
        b = int(e[i:i + 2], 16)
        out.append(round(a * (1 - amount) + b * amount))
    return "#" + "".join(f"{c:02x}" for c in out)


ANSI = {  # colorN -> semantic key (omarchy's ansi_alias table)
    "color0": "background", "color1": "red", "color2": "green",
    "color3": "yellow", "color4": "blue", "color5": "magenta",
    "color6": "cyan", "color7": "foreground", "color8": "muted",
    "color9": "bright_red", "color10": "bright_green",
    "color11": "bright_yellow", "color12": "bright_blue",
    "color13": "bright_magenta", "color14": "bright_cyan",
    "color15": "bright_foreground",
}


def resolve(raw: dict) -> dict:
    p = {k: str(v) for k, v in raw.items() if isinstance(v, str) and v.startswith("#")}

    # bidirectional ANSI <-> semantic aliasing
    for ansi, semantic in ANSI.items():
        if semantic not in p and ansi in raw:
            p[semantic] = raw[ansi]
        if ansi not in p and semantic in p:
            p[ansi] = p[semantic]
    p.setdefault("muted", p.get("dark_foreground", p.get("foreground", "#888888")))
    p["magenta"] = p.get("magenta", p.get("purple", "#ad8ee6"))
    p["bright_magenta"] = p.get("bright_magenta",
                                p.get("bright_purple",
                                     mix(p["magenta"], "#ffffff", 0.20)
                                     if "magenta" in p else "#bb9af7"))

    # brights default to 20% white (omarchy derivation)
    for base in ("red", "yellow", "green", "cyan", "blue"):
        key = f"bright_{base}"
        if key not in p and base in p:
            p[key] = mix(p[base], "#ffffff", 0.20)

    p["background"] = p.get("background", "#1a1b26")
    p["foreground"] = p.get("foreground", "#a9b1d6")
    p["bright_foreground"] = p.get("bright_foreground", p["foreground"])
    p["selection"] = p.get("selection", p["muted"])
    p["selection_foreground"] = p.get("selection_foreground", p["bright_foreground"])
    p["cursor"] = p.get("cursor", p["bright_foreground"])
    p["accent"] = p.get("accent", p.get("blue", p["foreground"]))
    p["color0"] = p["background"]
    p["color7"] = p["foreground"]
    p["color8"] = p["muted"]
    p["color15"] = p["bright_foreground"]

    # mode: explicit key, light.mode marker, else background luminance
    mode = raw.get("mode") or raw.get("theme_type")
    if not mode:
        light_marker = THEME_DIR / "light.mode"
        if light_marker.exists():
            mode = "light"
        else:
            bg = p["background"].lstrip("#")
            lum = sum(int(bg[i:i + 2], 16) for i in (0, 2, 4))
            mode = "light" if lum > 382 else "dark"
    p["mode"] = mode
    return p


# ------------------------------------------------------------ apply helpers ---

def log(action: str, detail: str = ""):
    print(f"{'[dry] ' if DRY else ''}{action}{': ' + detail if detail else ''}")


def gs(key: str, value: str):
    """gsettings set org.gnome.desktop.interface <key> <value>"""
    log(f"gsettings {key}", value)
    if DRY:
        return
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return
    subprocess.run(
        ["gsettings", "set", "org.gnome.desktop.interface", key, value],
        capture_output=True,
    )


def write(path: pathlib.Path, content: str, mode: str = "w"):
    log(f"write {path}", f"({len(content)} bytes)")
    if DRY:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.unlink()               # never write through nwg-look's gtk4 links
    path.write_text(content, encoding="utf-8") if mode == "w" else None


def hex_strip(c: str) -> str:
    return c.lstrip("#")


# ------------------------------------------------------------------- foot ----

def foot_ini(p: dict) -> str:
    """Generated foot palette — omarchy's foot.ini.tpl values.

    This foot build (1.28) rejects the classic [colors] section outright
    (check-config exit 230) and only accepts the scheme-conditional
    [colors-dark] / [colors-light] forms. Both get the same palette here so
    the theme applies whichever scheme the terminal resolves."""
    body = f"""foreground={hex_strip(p['foreground'])}
background={hex_strip(p['background'])}
selection-foreground={hex_strip(p['selection_foreground'])}
selection-background={hex_strip(p['selection'])}

cursor={hex_strip(p['background'])} {hex_strip(p['bright_foreground'])}

regular0={hex_strip(p['background'])}
regular1={hex_strip(p['red'])}
regular2={hex_strip(p['green'])}
regular3={hex_strip(p['yellow'])}
regular4={hex_strip(p['blue'])}
regular5={hex_strip(p['magenta'])}
regular6={hex_strip(p['cyan'])}
regular7={hex_strip(p['foreground'])}

bright0={hex_strip(p['muted'])}
bright1={hex_strip(p['bright_red'])}
bright2={hex_strip(p['bright_green'])}
bright3={hex_strip(p['bright_yellow'])}
bright4={hex_strip(p['bright_blue'])}
bright5={hex_strip(p['bright_magenta'])}
bright6={hex_strip(p['bright_cyan'])}
bright7={hex_strip(p['bright_foreground'])}
"""
    return f"[colors-dark]\n{body}\n[colors-light]\n{body}"


def foot_font_line() -> str:
    """Re-emit the `font=` line that regenerating foot.ini would destroy.

    set-text-size.sh owns this value: it prepends
    `font=<family>:size=<NN>` (fontconfig syntax — keys before the first
    section header ARE the [main] section) and records the size in
    state/text-size. Because foot_ini() returns the whole file rather than
    splicing a section, every theme switch used to write a palette-only
    foot.ini over it and drop the terminal back to foot's default size.

    family: read off the file being replaced, so a hand-edited family
    survives the rewrite; `monospace` otherwise, which is the same default
    set-text-size.sh falls back to when it finds no line at all.
    size:   state/text-size wins — it is what the settings row writes and
    what SettingsTextSizeRow reads back, so it beats a stale line.
    """
    family, size = "monospace", ""
    ini = HOME / ".config/foot/foot.ini"
    if ini.is_file():
        try:
            for line in ini.read_text(encoding="utf-8").splitlines():
                m = re.match(r"\s*font\s*=\s*(.+)$", line)
                if m:
                    spec = m.group(1).strip()
                    if ":size=" in spec:
                        family, size = spec.split(":size=", 1)
                    else:
                        family = spec
                    family = family.strip() or "monospace"
                    break
        except OSError:
            pass
    try:
        recorded = (HOME / ".local/state/quickshell/text-size").read_text(
            encoding="utf-8"
        ).strip()
    except OSError:
        recorded = ""
    if recorded:
        size = recorded
    return f"font={family}:size={size}\n\n" if size else ""


def foot_config_ok(content: str) -> bool:
    """set-text-size.sh's own gate, applied here too: a broken foot.ini is
    the terminal refusing to start. Validates the candidate in a private
    temp file so the real config is only ever replaced by a passing one."""
    if not shutil.which("foot"):
        return True
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", suffix=".ini", delete=False, encoding="utf-8"
        ) as f:
            f.write(content)
            tmp = f.name
        return (
            subprocess.run(
                ["foot", "--config", tmp, "--check-config"], capture_output=True
            ).returncode
            == 0
        )
    except OSError:
        return True
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def foot_osc(p: dict) -> bytes:
    """omarchy-theme-osc port: fg/bg/cursor/selection + the 16 ANSI slots."""
    out = b""

    def osc(code: str, value: str):
        nonlocal out
        out += f"\x1b]{code};{value}\x07".encode()

    osc("10", p["foreground"])          # text
    osc("11", p["background"])          # bg
    osc("12", p["cursor"])              # cursor
    osc("17", p["selection"])           # selection bg
    osc("19", p["selection_foreground"])
    for i in range(16):
        c = p.get(f"color{i}")
        if c:
            osc(f"4;{i}", c)
    return out


def running_foot_ttys():
    """TTYs of shells running inside foot — omarchy-theme-set-foot's loop:
    foot pid -> children -> fd/1 pointing at a pts."""
    ttys = set()
    pids = [int(d) for d in os.listdir("/proc") if d.isdigit()]
    comm = {}
    ppid = {}
    for pid in pids:
        try:
            comm[pid] = pathlib.Path(f"/proc/{pid}/comm").read_text().strip()
            stat = pathlib.Path(f"/proc/{pid}/stat").read_text()
            ppid[pid] = int(stat.split(") ", 1)[1].split()[1])
        except (OSError, IndexError, ValueError):
            continue
    feet = [pid for pid, c in comm.items() if c == "foot"]
    for child, parent in ppid.items():
        if parent in feet:
            try:
                target = os.readlink(f"/proc/{child}/fd/1")
            except OSError:
                continue
            if target.startswith("/dev/pts/"):
                ttys.add(target)
    return sorted(ttys)


def apply_foot(p: dict):
    palette = foot_ini(p)
    font = foot_font_line()
    content = font + palette
    # Colour is worth more than size: if the reconstructed font= line does
    # not survive check-config, drop just that line rather than hand foot a
    # config it refuses to parse. Skipped under --dry-run, which writes
    # nothing and so has nothing to protect.
    if font and not DRY and not foot_config_ok(content):
        log("foot.ini", "check-config rejected the font= line — writing palette only")
        content = palette
    write(HOME / ".config/foot/foot.ini", content)
    ttys = running_foot_ttys()
    if not ttys:
        log("foot OSC", "no running foot terminals")
        return
    log("foot OSC", f"{len(ttys)} tty(s)")
    if DRY:
        return
    seq = foot_osc(p)
    for tty in ttys:
        try:
            with open(tty, "wb") as f:
                f.write(seq)
        except OSError:
            pass


# ------------------------------------------------------------------ kitty ----

def apply_kitty(p: dict):
    conf = f"""foreground {p['foreground']}
background {p['background']}
selection_foreground {p['selection_foreground']}
selection_background {p['selection']}

cursor {p['bright_foreground']}
cursor_text_color {p['background']}

active_border_color {p['accent']}
active_tab_background {p['accent']}

color0 {p['background']}
color1 {p['red']}
color2 {p['green']}
color3 {p['yellow']}
color4 {p['blue']}
color5 {p['magenta']}
color6 {p['cyan']}
color7 {p['foreground']}
color8 {p['muted']}
color9 {p['bright_red']}
color10 {p['bright_green']}
color11 {p['bright_yellow']}
color12 {p['bright_blue']}
color13 {p['bright_magenta']}
color14 {p['bright_cyan']}
color15 {p['bright_foreground']}
"""
    write(HOME / ".config/kitty/current-theme.conf", conf)
    kc = HOME / ".config/kitty/kitty.conf"
    if not kc.exists():
        # no user config yet — seed one that pulls the generated palette in
        write(kc, "include current-theme.conf\n")


# --------------------------------------------------------------- chromium ----

def apply_chromium(p: dict):
    # chromium.theme.tpl is `{{ background_rgb }}`; the policy wants hex
    policy = {"BrowserThemeColor": p["background"], "BrowserColorScheme": "device"}
    stage = STATE / "browser-color.json"
    log("stage", f"{stage} -> {json.dumps(policy)}")
    if not DRY:
        STATE.mkdir(parents=True, exist_ok=True)
        stage.write_text(json.dumps(policy) + "\n")

    if not POLICY_DEST.parent.is_dir():
        log("chromium policy", "managed dir missing (run one-time-root-setup.sh)")
        return
    # 1) direct write if somehow writable  2) passwordless helper  3) skip
    if DRY:
        log("chromium policy", f"push to {POLICY_DEST}")
        return
    try:
        with open(POLICY_DEST, "w") as f:
            f.write(json.dumps(policy) + "\n")
        log("chromium policy", "direct write ok")
    except OSError:
        r = subprocess.run(["sudo", "-n", BROWSER_HELPER], capture_output=True)
        if r.returncode == 0:
            log("chromium policy", "via passwordless helper")
        else:
            log("chromium policy", "not pushed (no root yet)")

    # refresh a running browser the way omarchy does
    if subprocess.run(["pgrep", "-x", "chromium"], capture_output=True).returncode == 0:
        subprocess.Popen(
            ["chromium", "--refresh-platform-policy", "--no-startup-window"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        log("chromium", "refreshed running instance")


# ----------------------------------------------------------------- gsettings --

def current_gtk_theme() -> str:
    """The GTK theme currently configured (nwg-look / gsettings) — the
    user's own choice, read before we overwrite anything."""
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return ""
    r = subprocess.run(
        ["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
        capture_output=True, text=True,
    )
    return r.stdout.strip().strip("'\"") if r.returncode == 0 else ""


def gtk_theme_name(p: dict, current: str) -> str:
    """Sticky base + per-theme mode: whatever GTK theme the user picked
    (adw-gtk3, Yaru-sage, …) stays the theme across switches; only the
    light/dark variant follows each quickshell theme's mode
    (adw-gtk3 <-> adw-gtk3-dark), guarded on the directory existing.
    Nothing custom configured -> omarchy's stock Adwaita/Adwaita-dark."""
    if current:
        base = current[:-5] if current.endswith("-dark") else current
        if base and base not in ("Adwaita", "Default"):
            candidate = base if p["mode"] == "light" else f"{base}-dark"
            if (pathlib.Path("/usr/share/themes") / candidate).is_dir():
                return candidate
            log("gtk-theme", f"{candidate} not installed — falling back")
    return "Adwaita" if p["mode"] == "light" else "Adwaita-dark"


def apply_gsettings(p: dict):
    """omarchy-theme-set-gnome port: scheme + icons per theme; GTK theme =
    the user's sticky choice flipped to this theme's mode."""
    scheme = "prefer-light" if p["mode"] == "light" else "prefer-dark"

    # per-theme icon variant (icons.theme), defaults to omarchy's Yaru-blue
    icons_file = THEME_DIR / "icons.theme"
    icons = icons_file.read_text().strip() if icons_file.is_file() else "Yaru-blue"
    gtk = gtk_theme_name(p, current_gtk_theme())

    gs("color-scheme", f"'{scheme}'")
    gs("gtk-theme", f"'{gtk}'")
    if (pathlib.Path("/usr/share/icons") / icons).is_dir():
        gs("icon-theme", f"'{icons}'")
    else:
        log("icon-theme", f"{icons} not installed yet — keeping current")
    return gtk, scheme, icons


def apply_gtk_ini(gtk: str, scheme: str, icons: str, have_icons: bool):
    """Merge into settings.ini instead of overwriting — nwg-look writes a
    full block there (font, cursor, xft) that must survive theme switches.
    Non-GNOME sessions (this Hyprland box) read settings.ini, not gsettings."""
    prefer_dark = "1" if scheme == "prefer-dark" else "0"
    updates = {
        "gtk-theme-name": gtk,
        "gtk-application-prefer-dark-theme": prefer_dark,
    }
    if have_icons:
        updates["gtk-icon-theme-name"] = icons
    for ini in (HOME / ".config/gtk-3.0/settings.ini",
                HOME / ".config/gtk-4.0/settings.ini"):
        merge_kv(ini, updates, "=")


def apply_xsettingsd(gtk: str, icons: str, have_icons: bool):
    """nwg-look exports an xsettingsd.conf (dormant until the daemon runs);
    keep Net/* in sync so XWayland apps agree if it's ever started."""
    path = HOME / ".config/xsettingsd/xsettingsd.conf"
    if not path.is_file():
        return
    updates = {"Net/ThemeName": gtk}
    if have_icons:
        updates["Net/IconThemeName"] = icons
    merge_kv(path, {k: f'"{v}"' for k, v in updates.items()}, " ",
             key_prefix_quoted=True)


def merge_kv(path: pathlib.Path, updates: dict, sep: str,
             key_prefix_quoted: bool = False):
    """Update key lines in a flat config, preserving every other line —
    settings.ini keys are bare (gtk-theme-name=x), xsettingsd keys carry a
    quoted value after a space (Net/ThemeName \"x\")."""
    lines = path.read_text().splitlines() if path.is_file() else []
    if sep == "=" and not any(l.strip() == "[Settings]" for l in lines):
        lines.insert(0, "[Settings]")
    out, applied = [], set()

    def key_of(line: str):
        s = line.strip()
        if not s or s[:1] in ("#", "["):
            return None
        if key_prefix_quoted:
            return s.split(None, 1)[0] if s.split(None, 1)[0] in updates else None
        return s.split(sep, 1)[0].strip() if sep in s else None

    for line in lines:
        key = key_of(line)
        if key in updates:
            if key in applied:
                continue
            applied.add(key)
            out.append(f"{key}{sep}{updates[key]}" if sep == "="
                       else f"{key} {updates[key]}")
        else:
            out.append(line)
    for key, value in updates.items():          # keys absent yet -> append
        if key not in applied:
            out.append(f"{key}{sep}{value}" if sep == "="
                       else f"{key} {value}")
    log(f"merge {path}", ", ".join(f"{k}{sep}{v}" for k, v in updates.items()))
    if not DRY:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(out) + "\n", encoding="utf-8")


# ---------------------------------------------------------- gtk custom colors --

def rgb_sum(c: str) -> int:
    h = c.lstrip("#")
    return sum(int(h[i:i + 2], 16) for i in (0, 2, 4))


def ramp(c: str):
    """GNOME palette scale _1 (lightest) .. _5 (darkest) from a base color."""
    return [mix(c, "#ffffff", 0.65), mix(c, "#ffffff", 0.35), c,
            mix(c, "#000000", 0.25), mix(c, "#000000", 0.45)]


def gtk_color_map(p: dict) -> dict:
    """colors.toml palette -> the named colors an adwaita-lineage GTK theme
    declares with @define-color. Emission intersects with the names the
    active theme actually defines, so odd themes never get bogus lines."""
    g = p.get
    bg, fg = p["background"], p["foreground"]
    dark_bg = g("dark_background", bg)
    light_bg = g("lighter_background", bg)
    accent = p["accent"]

    def on(c: str) -> str:
        # readable text on surface c: dark ink on light, light ink on dark
        return bg if rgb_sum(c) > 382 else p["bright_foreground"]

    m = {
        # surfaces
        "window_bg_color": bg,          "window_fg_color": fg,
        "view_bg_color": dark_bg,       "view_fg_color": fg,
        "headerbar_bg_color": light_bg, "headerbar_fg_color": fg,
        "sidebar_bg_color": dark_bg,    "sidebar_fg_color": fg,
        "card_bg_color": light_bg,      "card_fg_color": fg,
        "popover_bg_color": light_bg,   "popover_fg_color": fg,
        "dialog_bg_color": light_bg,    "dialog_fg_color": fg,
        "panel_bg_color": bg,           "panel_fg_color": fg,
        "content_view_bg": dark_bg,     "text_view_bg": dark_bg,
        # accent
        "accent_color": accent, "accent_bg_color": accent,
        "accent_fg_color": on(accent),
        # classic GTK3 names some widgets still use
        "theme_bg_color": bg,        "theme_fg_color": fg,
        "theme_base_color": dark_bg, "theme_text_color": fg,
        "theme_selected_bg_color": accent,
        "theme_selected_fg_color": on(accent),
    }
    # semantics (guarded — every omarchy theme ships the palette, but don't crash)
    for prefix, key in (("error", "red"), ("destructive", "red"),
                        ("success", "green"), ("warning", "yellow")):
        c = g(key)
        if c:
            m[f"{prefix}_color"] = c
            m[f"{prefix}_bg_color"] = c
            m[f"{prefix}_fg_color"] = on(c)
    # GNOME palette ramps driven by the theme's ANSI colors (purple = magenta)
    for name, key in (("blue", "blue"), ("green", "green"), ("yellow", "yellow"),
                      ("orange", "orange"), ("red", "red"), ("purple", "magenta"),
                      ("brown", "brown")):
        c = g(key)
        if c:
            for i, shade in enumerate(ramp(c), 1):
                m[f"{name}_{i}"] = shade
    return m


CORE_DEFINE_NAMES = {
    "window_bg_color", "window_fg_color", "view_bg_color", "view_fg_color",
    "headerbar_bg_color", "headerbar_fg_color", "sidebar_bg_color",
    "sidebar_fg_color", "card_bg_color", "card_fg_color", "popover_bg_color",
    "popover_fg_color", "accent_color", "accent_bg_color", "accent_fg_color",
    "theme_bg_color", "theme_fg_color", "theme_base_color",
    "theme_text_color", "theme_selected_bg_color", "theme_selected_fg_color",
    "error_color", "error_bg_color", "error_fg_color", "destructive_color",
    "destructive_bg_color", "destructive_fg_color", "success_color",
    "success_bg_color", "success_fg_color", "warning_color",
    "warning_bg_color", "warning_fg_color",
}


def theme_define_names(gtk: str, rel: str) -> set:
    """@define-color names the active theme declares (empty set if the
    theme ships no such file, e.g. stock Adwaita with no directory)."""
    css = pathlib.Path("/usr/share/themes") / gtk / rel
    if css.is_file():
        return set(re.findall(r"@define-color\s+([a-z_0-9]+)",
                              css.read_text(errors="ignore")))
    return set()


def define_block(p: dict, names: set) -> str:
    cmap = gtk_color_map(p)
    wanted = names or CORE_DEFINE_NAMES
    lines = [f"@define-color {k} {cmap[k]};"
             for k in sorted(cmap) if k in wanted]
    header = (f"/* quickshell custom colors: {THEME_DIR.name} "
              f"(generated by global-theme.py — do not edit) */")
    return header + "\n" + "\n".join(lines) + "\n"


def apply_gtk3_css(p: dict, gtk: str):
    """Custom colors for GTK3: a user gtk.css @define-color block. GTK3
    resolves the theme's color references lazily against the last
    definition across providers, so this recolors the whole active theme
    (proven live: nwg-look rendered fully red from a 4-line block)."""
    names = theme_define_names(gtk, "gtk-3.0/gtk.css")
    if not names:
        log("gtk3 css", f"{gtk} declares no palette — skipping")
        return
    write(HOME / ".config/gtk-3.0/gtk.css", define_block(p, names))


def apply_gtk4_css(p: dict, gtk: str):
    """Custom colors for libadwaita apps: replace nwg-look's gtk4 symlink
    with a real file = the theme's own imports (relative urls re-pointed at
    the theme dir) followed by the same define block — libadwaita.css
    defines its palette in-file, and last-definition-wins puts ours on top."""
    theme_gtk4 = pathlib.Path("/usr/share/themes") / gtk / "gtk-4.0"
    names = theme_define_names(gtk, "gtk-4.0/libadwaita.css")
    if not names and not (theme_gtk4 / "gtk.css").is_file():
        log("gtk4 css", f"{gtk} has no gtk-4.0 side — leaving user file")
        return

    def build(src_name: str) -> str:
        src = theme_gtk4 / src_name
        if not src.is_file():
            src = theme_gtk4 / "gtk.css"
        imports = []
        for line in src.read_text(errors="ignore").splitlines():
            s = line.strip()
            if s.startswith("@import"):
                s = re.sub(r"url\(\s*['\"]?(?!file:)([^'\")]+)['\"]?\s*\)",
                           lambda m: f"url('file://{theme_gtk4}/{m.group(1)}')", s)
            imports.append(s)
        return "\n".join(imports) + "\n" + define_block(p, names)

    write(HOME / ".config/gtk-4.0/gtk.css", build("gtk.css"))
    if (theme_gtk4 / "gtk-dark.css").is_file():
        write(HOME / ".config/gtk-4.0/gtk-dark.css", build("gtk-dark.css"))


# ---------------------------------------------------------------- hyprland ---

def hypr_border_value(spec: str) -> str:
    """colors.toml border spec -> Lua value for hl.config. Single color
    stays a quoted string; a gradient becomes { colors = {..}, angle = N }
    (the Lua API rejects multi-color strings — probe-verified). Mirrors
    omarchy's hypr_gradient helper in omarchy-theme-set-templates."""
    colors = re.findall(r"rgba?\([0-9a-fA-F]+\)", spec or "")
    if len(colors) <= 1:
        return f'"{spec}"'
    angle = re.search(r"(\d+)deg", spec)
    joined = ", ".join(f'"{c}"' for c in colors)
    return f'{{ colors = {{ {joined} }}, angle = {angle.group(1) if angle else 0} }}'


def apply_hyprland(p: dict, raw: dict):
    """Generate ~/.config/hypr/colors.lua — hyprland.lua require()s it last
    (pcall), hl.config deep-merges into appearance.lua, and switch-theme.sh
    hyprctl-reloads after this script. Mirrors omarchy's hyprland.lua.tpl:
    per-theme hyprland_active/inactive_border keys win when shipped, else
    accent->cyan45 gradient + muted grey; group borders track the same and
    the window shadow tints toward the theme background."""
    accent = p["accent"].lstrip("#")
    cyan = p.get("cyan", p["accent"]).lstrip("#")
    muted = p.get("muted", p["accent"]).lstrip("#")

    active_spec = str(raw.get("hyprland_active_border") or "")
    inactive_spec = str(raw.get("hyprland_inactive_border") or "")
    active = (hypr_border_value(active_spec) if active_spec
              else f'{{ colors = {{"rgba({accent}ee)", "rgba({cyan}ee)"}}, angle = 45 }}')
    inactive = f'"{inactive_spec}"' if inactive_spec else f'"rgba({muted}aa)"'
    shadow = mix(p["background"], "#000000", 0.7).lstrip("#")

    log("hyprland borders", f"active {active}  inactive {inactive}")
    body = f"""-- quickshell theme colors: {THEME_DIR.name} (generated by switch-theme.sh — do not edit)
-- omarchy's hyprland_* keys win when the theme ships them; fallback is an
-- accent->cyan gradient and muted grey. hyprland.lua require()s this file
-- last; hl.config deep-merges over appearance.lua (probe-verified).
hl.config({{
  general = {{
    col = {{
      active_border   = {active},
      inactive_border = {inactive},
    }},
  }},

  group = {{
    col = {{
      border_active   = {active},
      border_inactive = {inactive},
    }},
  }},

  decoration = {{
    shadow = {{ color = 0xee{shadow} }},
  }},
}})
"""
    write(HOME / ".config/hypr/colors.lua", body)

    if DRY:
        return
    if shutil.which("hyprctl") and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        r = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True)
        log("hyprctl reload", "ok" if r.returncode == 0
            else f"failed: {(r.stderr or r.stdout).strip()[:60]}")
    else:
        log("hyprctl reload", "no running Hyprland — colors apply next start")


def apply_btop(p: dict):
    """~/.config/btop/themes/quickshell-<theme>.theme built from colors.toml,
    plus color_theme switched in btop.conf (merged — presets/update_ms/...
    survive). Layout mirrors shipped themes: accent/cyan/bright for CPU
    graphs, yellow->orange->red heat for temps, single-color memory segments
    (green/blue/accent/red), two-color net gradients, muted box outlines."""
    accent = p["accent"]

    def c(key: str) -> str:
        return p.get(key) or accent

    cyan, blue, green = c("cyan"), c("blue"), c("green")
    yellow, orange, red = c("yellow"), c("orange"), c("red")
    selection = p.get("selection") or accent
    bright = p.get("bright_foreground") or p["foreground"]
    muted = p.get("muted") or accent
    name = f"quickshell-{THEME_DIR.name}"

    lines = [
        f"# quickshell theme colors: {THEME_DIR.name} "
        "(generated by global-theme.py — do not edit)",
        "",
        f'theme[main_bg]="{p["background"]}"',
        f'theme[main_fg]="{p["foreground"]}"',
        f'theme[title]="{accent}"',
        f'theme[hi_fg]="{cyan}"',
        f'theme[selected_bg]="{selection}"',
        f'theme[selected_fg]="{bright}"',
        f'theme[inactive_fg]="{muted}"',
        f'theme[proc_misc]="{accent}"',
        "",
    ]
    lines += [f'theme[{k}]="{muted}"'
              for k in ("cpu_box", "mem_box", "net_box", "proc_box", "div_line")]
    lines += [
        "",
        # temperature: heat ramp
        f'theme[temp_start]="{yellow}"',
        f'theme[temp_mid]="{orange}"',
        f'theme[temp_end]="{red}"',
        # cpu graph: accent -> cyan -> bright (shipped nord's structure)
        f'theme[cpu_start]="{accent}"',
        f'theme[cpu_mid]="{cyan}"',
        f'theme[cpu_end]="{bright}"',
        # memory/disk meters: one flat color per segment (mid/end empty)
        f'theme[free_start]="{green}"',
        'theme[free_mid]=""',
        'theme[free_end]=""',
        f'theme[cached_start]="{blue}"',
        'theme[cached_mid]=""',
        'theme[cached_end]=""',
        f'theme[available_start]="{accent}"',
        'theme[available_mid]=""',
        'theme[available_end]=""',
        f'theme[used_start]="{red}"',
        'theme[used_mid]=""',
        'theme[used_end]=""',
        # net graphs: two-color gradients (start/end, empty mid)
        f'theme[download_start]="{cyan}"',
        'theme[download_mid]=""',
        f'theme[download_end]="{blue}"',
        f'theme[upload_start]="{orange}"',
        'theme[upload_mid]=""',
        f'theme[upload_end]="{red}"',
    ]
    write(HOME / ".config/btop/themes" / f"{name}.theme", "\n".join(lines) + "\n")

    conf = HOME / ".config/btop/btop.conf"
    out, applied = [], False
    for line in (conf.read_text().splitlines() if conf.is_file() else []):
        if line.strip().startswith("color_theme"):
            if not applied:
                out.append(f'color_theme = "{name}"')
                applied = True
        else:
            out.append(line)
    if not applied:
        out.append(f'color_theme = "{name}"')
    log(f"merge {conf}", f'color_theme = "{name}"')
    if not DRY:
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text("\n".join(out) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------- nvim ---

def apply_nvim(p: dict):
    """~/.config/nvim/colors/quickshell.lua — a full colorscheme baked from the
    palette; LazyVim loads it through lua/plugins/quickshell.lua on startup.
    Skipped when ~/.config/nvim is absent (nvim not installed)."""
    nvim_dir = HOME / ".config/nvim"
    if not nvim_dir.is_dir():
        log("skip nvim", "no ~/.config/nvim")
        return
    accent = p["accent"]

    def c(key: str) -> str:
        return p.get(key) or accent

    red, orange, yellow = c("red"), c("orange"), c("yellow")
    green, cyan, blue, magenta = c("green"), c("cyan"), c("blue"), c("magenta")
    bg, fg = p["background"], p["foreground"]
    sel = p.get("selection") or accent
    muted = p.get("muted") or accent
    bright = p.get("bright_foreground") or fg
    lighter = mix(bg, fg, 0.06)
    ansi = [p.get(f"color{i}") or (bg if i == 0 else
                                   fg if i == 15 else accent)
            for i in range(16)]

    rows = []

    def h(name: str, fg_: str = None, bg_: str = None, bold=False,
          italic=False, underline=False, reverse=False):
        parts = []
        if fg_:
            parts.append(f'fg = "{fg_}"')
        if bg_:
            parts.append(f'bg = "{bg_}"')
        if bold:
            parts.append("bold = true")
        if italic:
            parts.append("italic = true")
        if underline:
            parts.append("underline = true")
        if reverse:
            parts.append("reverse = true")
        rows.append(f'  ["{name}"] = {{ {", ".join(parts)} }},')

    # syntax (standard groups cover regex highlighting; @-groups override for
    # treesitter, which links to these by default anyway)
    h("Normal", fg_=fg, bg_=bg)
    h("NormalFloat", fg_=fg, bg_=lighter)
    h("Comment", fg_=muted, italic=True)
    h("Constant", fg_=orange)
    h("String", fg_=green)
    h("Character", fg_=green)
    h("Number", fg_=orange)
    h("Boolean", fg_=orange)
    h("Float", fg_=orange)
    h("Identifier", fg_=fg)
    h("Function", fg_=accent)
    h("Statement", fg_=magenta)
    h("Conditional", fg_=magenta)
    h("Repeat", fg_=magenta)
    h("Label", fg_=magenta)
    h("Operator", fg_=cyan)
    h("Keyword", fg_=magenta)
    h("Exception", fg_=magenta)
    h("PreProc", fg_=cyan)
    h("Include", fg_=cyan)
    h("Define", fg_=cyan)
    h("Macro", fg_=cyan)
    h("Type", fg_=yellow)
    h("StorageClass", fg_=yellow)
    h("Structure", fg_=yellow)
    h("Typedef", fg_=yellow)
    h("Special", fg_=cyan)
    h("SpecialChar", fg_=cyan)
    h("Tag", fg_=magenta)
    h("SpecialComment", fg_=muted, italic=True)
    h("Underlined", underline=True)
    h("Bold", bold=True)
    h("Italic", italic=True)
    h("Error", fg_=red, bold=True)
    h("Todo", fg_=bg, bg_=yellow, bold=True)
    h("ErrorMsg", fg_=red, bold=True)
    h("WarningMsg", fg_=orange)
    h("Title", fg_=accent, bold=True)
    h("Question", fg_=accent)
    h("MoreMsg", fg_=accent)
    h("ModeMsg", fg_=fg, bold=True)

    # editor chrome
    h("LineNr", fg_=muted)
    h("CursorLine", bg_=lighter)
    h("CursorLineNr", fg_=accent, bold=True)
    h("CursorColumn", bg_=lighter)
    h("ColorColumn", bg_=lighter)
    h("Cursor", reverse=True)
    h("Visual", bg_=sel)
    h("VisualNOS", bg_=sel)
    h("Search", fg_=bg, bg_=yellow)
    h("IncSearch", fg_=bg, bg_=orange)
    h("CurSearch", fg_=bg, bg_=orange)
    h("MatchParen", fg_=accent, bold=True)
    h("StatusLine", fg_=fg, bg_=lighter)
    h("StatusLineNC", fg_=muted, bg_=lighter)
    h("WinBar", fg_=accent, bg_=bg, bold=True)
    h("WinBarNC", fg_=muted, bg_=bg)
    h("TabLine", fg_=muted, bg_=lighter)
    h("TabLineFill", bg_=lighter)
    h("TabLineSel", fg_=fg, bg_=bg, bold=True)
    h("Pmenu", fg_=fg, bg_=lighter)
    h("PmenuSel", fg_=bright, bg_=sel)
    h("PmenuSbar", bg_=lighter)
    h("PmenuThumb", bg_=muted)
    h("WildMenu", fg_=bright, bg_=sel)
    h("WinSeparator", fg_=muted)
    h("VertSplit", fg_=muted)
    h("SignColumn", fg_=muted, bg_=bg)
    h("Folded", fg_=muted, bg_=lighter)
    h("FoldColumn", fg_=muted, bg_=bg)
    h("QuickFixLine", bg_=sel)
    h("NonText", fg_=muted)
    h("SpecialKey", fg_=muted)
    h("Whitespace", fg_=muted)
    h("EndOfBuffer", fg_=bg)

    # diffs + diagnostics
    h("DiffAdd", fg_=green)
    h("DiffChange", fg_=yellow)
    h("DiffDelete", fg_=red)
    h("DiffText", fg_=yellow, bold=True)
    h("DiagnosticError", fg_=red)
    h("DiagnosticWarn", fg_=orange)
    h("DiagnosticInfo", fg_=cyan)
    h("DiagnosticHint", fg_=blue)
    h("DiagnosticOk", fg_=green)
    h("LspReferenceText", bg_=sel)
    h("LspReferenceRead", bg_=sel)
    h("LspReferenceWrite", bg_=sel)

    # treesitter captures (lua, vimdoc, ...)
    h("@comment", fg_=muted, italic=True)
    h("@keyword", fg_=magenta)
    h("@keyword.function", fg_=magenta)
    h("@keyword.return", fg_=magenta)
    h("@keyword.operator", fg_=cyan)
    h("@function", fg_=accent)
    h("@function.builtin", fg_=cyan)
    h("@function.call", fg_=accent)
    h("@function.method", fg_=accent)
    h("@function.method.call", fg_=accent)
    h("@constructor", fg_=yellow)
    h("@string", fg_=green)
    h("@string.escape", fg_=cyan)
    h("@number", fg_=orange)
    h("@boolean", fg_=orange)
    h("@constant", fg_=orange)
    h("@constant.builtin", fg_=orange)
    h("@variable", fg_=fg)
    h("@variable.builtin", fg_=cyan)
    h("@variable.parameter", fg_=fg)
    h("@variable.member", fg_=fg)
    h("@property", fg_=fg)
    h("@field", fg_=fg)
    h("@type", fg_=yellow)
    h("@type.builtin", fg_=yellow)
    h("@type.definition", fg_=yellow)
    h("@attribute", fg_=cyan)
    h("@operator", fg_=cyan)
    h("@punctuation.delimiter", fg_=fg)
    h("@punctuation.bracket", fg_=fg)
    h("@punctuation.special", fg_=cyan)
    h("@tag", fg_=magenta)
    h("@tag.attribute", fg_=cyan)
    h("@tag.delimiter", fg_=muted)
    h("@module", fg_=fg)
    h("@module.builtin", fg_=cyan)
    h("@label", fg_=magenta)
    h("@markup.heading", fg_=accent, bold=True)
    h("@markup.link", fg_=cyan, underline=True)
    h("@markup.list", fg_=magenta)

    lua = "\n".join([
        f"-- quickshell colorscheme: {THEME_DIR.name} "
        "(generated by global-theme.py — do not edit)",
        "local hi = vim.api.nvim_set_hl",
        "",
        "vim.o.termguicolors = true",
        'vim.g.colors_name = "quickshell"',
        "",
        "-- ANSI palette for :terminal buffers",
        *[f'vim.g.terminal_color_{i} = "{ansi[i]}"' for i in range(16)],
        "",
        "local groups = {",
        *rows,
        "}",
        "",
        "for name, spec in pairs(groups) do",
        "  hi(0, name, spec)",
        "end",
        "",
        'return { name = "quickshell" }',
        "",
    ])
    write(nvim_dir / "colors/quickshell.lua", lua)


# --------------------------------------------------------------------- main ---

if len(sys.argv) < 2 or sys.argv[1].startswith("--"):
    print(__doc__)
    sys.exit(1)

THEME_DIR = pathlib.Path(sys.argv[1]).expanduser()
if not THEME_DIR.is_dir():
    print(f"global-theme: no such theme dir {THEME_DIR}", file=sys.stderr)
    sys.exit(1)

toml_file = THEME_DIR / "colors.toml"
raw = {}
if toml_file.is_file():
    with open(toml_file, "rb") as f:
        raw = tomllib.load(f)

p = resolve(raw)
log("theme", f"{THEME_DIR.name} ({p['mode']})")

# prebuild mode: python3 global-theme.py <dir> --btop-only writes just the
# btop theme (used to render every theme's .theme up front)
if "--btop-only" in sys.argv:
    apply_btop(p)
    log("done", "btop theme built only")
    sys.exit(0)

gtk, scheme, icons = apply_gsettings(p)
icons_file = THEME_DIR / "icons.theme"
have_icons = icons_file.is_file() and (pathlib.Path("/usr/share/icons") / icons).is_dir()
apply_gtk_ini(gtk, scheme, icons, have_icons)
apply_xsettingsd(gtk, icons, have_icons)
apply_gtk3_css(p, gtk)
apply_gtk4_css(p, gtk)
apply_foot(p)
apply_kitty(p)
apply_chromium(p)
apply_hyprland(p, raw)
apply_btop(p)
apply_nvim(p)
log("done", "global theming applied")
