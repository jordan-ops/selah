#!/usr/bin/env python3
"""Global theming — omarchy-style app coordination for this quickshell setup.

Ports the user-session half of omarchy's post-theme hooks to switch-theme.sh:

  * omarchy-theme-set-gnome   -> gsettings color-scheme / gtk-theme / icon-theme
  * (nwg-look equivalent)     -> gtk-3.0 + gtk-4.0 settings.ini
  * omarchy-theme-set-foot    -> generated foot.ini + live OSC to running footes
  * kitty.conf.tpl            -> generated current-theme.conf (+ include shim)
  * omarchy-theme-set-browser -> staged browser-color.json + best-effort push
                                 to /etc/chromium/policies/managed/color.json
  * firefox                   -> profile userChrome.css + userContent.css and
                                 the three prefs that switch them on (no policy
                                 hook exists for Gecko, so this is profile-level)
  * yaru folders              -> ~/.local/share/icons/quickshell-folders, an
                                 icon theme inheriting the theme's Yaru variant
                                 whose folder art is tinted to its accent

Everything user-session runs directly; the /etc policy write tries a direct
write, then `sudo -n` (the passwordless helper one-time-root-setup.sh installs),
then gives up silently — the staged JSON stays current so the policy catches up
on the next run after setup.

Usage: global-theme.py <theme-dir> [--dry-run]
"""

import colorsys
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

# Pillow only backs the Yaru folder tint; everything else in the retint is
# text in/text out, so a box without it degrades to "no folder colours"
# instead of failing the switch.
try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None

HOME = pathlib.Path.home()
STATE = HOME / ".local/state/quickshell/generated"
# The user's sticky GTK choice, recorded so it survives a machine that has
# no dconf history yet (fresh install, or a theme applied from a TTY).
GTK_STATE = HOME / ".local/state/quickshell/current-gtk-theme"
POLICY_DEST = pathlib.Path("/etc/chromium/policies/managed/color.json")
BROWSER_HELPER = "/usr/local/bin/set-browser-color"

# Firefox has no /etc policy to push colours through, so everything lives in
# the profile instead. The Install<hash> section is how modern Firefox (67+)
# picks the default profile for a given install: without it Firefox ignores a
# hand-written profiles.ini and mints its own profile on first run. The hash
# is a function of the install path (proven: same path -> same hash across
# HOMEs, /tmp copy at another path -> different hash), so it is *discovered*
# from installs.ini whenever Firefox has already run, and read from this state
# seed only for the never-launched case.
FF_DIR = HOME / ".mozilla/firefox"
FF_STATE = HOME / ".local/state/quickshell/firefox-install-hash"
FF_PROFILE = "selah.default-release"   # our profile when we have to seed one

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


# ----------------------------------------------------------------- firefox ---

def ini_sections(text: str) -> dict:
    """profiles.ini / installs.ini -> {section: {key: value}}.

    Both are flat INIs written by Firefox itself (no quoting, no nesting), so
    a 15-line parse beats pulling in configparser — which would also choke on
    the section names Firefox uses as bare words."""
    sections, current = {}, None
    for line in text.splitlines():
        s = line.strip()
        if not s or s[0] in ";#":
            continue
        if s.startswith("[") and s.endswith("]"):
            current = s[1:-1]
            sections.setdefault(current, {})
        elif current is not None and "=" in s:
            key, value = s.split("=", 1)
            sections[current][key.strip()] = value.strip()
    return sections


def firefox_install_hash(sections: dict) -> str:
    """`4F96D1932A9F858E` out of an `[Install4F96D1932A9F858E]` section, else ""."""
    for name in sections:
        if name.startswith("Install") and len(name) > len("Install"):
            return name[len("Install"):]
    return ""


def firefox_profile():
    """Resolve the profile Gecko will actually open: (dir, install hash).

    Order mirrors what the browser does: the per-install entry wins (it is
    written by Firefox itself and is the one thing it refuses to second-guess),
    then the legacy `Default=1` / `[General] Default=` markers for older
    layouts, then the only profile when there is exactly one. Returns
    (None, "") when nothing resolves, which is the seed case below."""
    if not FF_DIR.is_dir():
        return None, ""

    for name in ("installs.ini", "profiles.ini"):
        path = FF_DIR / name
        if not path.is_file():
            continue
        sections = ini_sections(path.read_text(encoding="utf-8", errors="ignore"))
        for section, kv in sections.items():
            if section.startswith("Install") and kv.get("Default"):
                target = kv["Default"]
                if not kv.get("IsRelative", "1") or pathlib.PurePath(target).is_absolute():
                    resolved = pathlib.Path(target)
                else:
                    resolved = FF_DIR / target
                return (resolved if resolved.is_dir() else None), firefox_install_hash(sections)

    ini = FF_DIR / "profiles.ini"
    if not ini.is_file():
        return None, ""
    sections = ini_sections(ini.read_text(encoding="utf-8", errors="ignore"))
    hash_ = firefox_install_hash(sections)

    candidates = []
    general = sections.get("General", {})
    if general.get("Default") is not None:
        candidates.append(f"Profile{general['Default']}")
    for section, kv in sections.items():
        if section.startswith("Profile") and kv.get("Default") == "1":
            candidates.append(section)
    if not candidates:
        profiles = [s for s in sections if s.startswith("Profile")]
        if len(profiles) == 1:
            candidates = profiles
    for section in candidates:
        kv = sections.get(section, {})
        if kv.get("Path"):
            resolved = (pathlib.Path(kv["Path"]) if kv.get("IsRelative") == "0"
                        else FF_DIR / kv["Path"])
            if resolved.is_dir():
                return resolved, hash_
    return None, hash_


def firefox_needs_seed() -> bool:
    """True when Firefox has clearly never run here: no profiles.ini at all,
    or one that lists no profiles. Anything else belongs to Firefox — this
    script writes into the profile Gecko chose, it never re-points a profile
    list it does not understand."""
    if not FF_DIR.is_dir():
        return True
    ini = FF_DIR / "profiles.ini"
    if not ini.is_file():
        return True
    sections = ini_sections(ini.read_text(encoding="utf-8", errors="ignore"))
    return not any(name.startswith("Profile") for name in sections)


def seed_firefox_profile():
    """First run on a machine Firefox has never opened: make the profile that
    the desktop will theme, and — when the install hash is known — claim it as
    this install's default so Gecko opens *it* instead of minting an
    unthemed `xxxxxxxx.default-release` beside it.

    Without the hash this still writes the profile; Firefox then picks its own
    and the next switch finds it through installs.ini (self-healing, just one
    launch late)."""
    target = FF_DIR / FF_PROFILE
    if DRY:
        log("firefox profile", f"seed {target}")
        return target
    target.mkdir(parents=True, exist_ok=True)

    ini = FF_DIR / "profiles.ini"
    existing = ""
    if ini.is_file():
        existing = ini.read_text(encoding="utf-8", errors="ignore")
    body = existing if existing.strip() else "[General]\nVersion=2\n\n[Profile0]\nName=selah\nIsRelative=1\nPath=" + FF_PROFILE + "\nDefault=1\n"
    if not ini.is_file():
        write(ini, body)

    hash_ = ""
    sections = ini_sections(existing) if existing else {}
    hash_ = firefox_install_hash(sections)
    if not hash_ and FF_STATE.is_file():
        hash_ = FF_STATE.read_text(encoding="utf-8").strip()
    if hash_ and f"[Install{hash_}]" not in body:
        if not body.endswith("\n"):
            body += "\n"
        write(ini, body + f"\n[Install{hash_}]\nDefault={FF_PROFILE}\nLocked=1\n")
        log("firefox profile", f"claimed as default for install {hash_}")
    elif not hash_:
        log("firefox profile", "install hash unknown — Firefox picks the profile on first launch")
    return target


def claim_firefox_install(profile: pathlib.Path) -> bool:
    """Write the `[Install<hash>]` claim Firefox writes on its own first
    launch, when the hash came from the seeded state file instead.

    Without it a profiles.ini this script wrote before the hash was known
    would make Gecko mint an unthemed `xxxxxxxx.default-release` beside the
    profile we just themed — the same late-by-one-launch heal as the seed
    path, only without waiting for it. Returns True when something was
    written."""
    if not FF_STATE.is_file():
        return False
    hash_ = FF_STATE.read_text(encoding="utf-8").strip()
    if not hash_:
        return False
    ini = FF_DIR / "profiles.ini"
    text = ini.read_text(encoding="utf-8", errors="ignore") if ini.is_file() else ""
    if f"[Install{hash_}]" in text:
        return False
    try:
        target = profile.relative_to(FF_DIR).as_posix()
    except ValueError:
        # a profile Firefox was pointed at elsewhere — its path rules, not ours
        target = str(profile)
    body = text
    if body and not body.endswith("\n"):
        body += "\n"
    if body:
        body += "\n"
    write(ini, body + f"[Install{hash_}]\nDefault={target}\nLocked=1\n")
    return True


def readable_on(c: str, p: dict) -> str:
    """Readable ink for a surface of colour c: dark on light, light on dark —
    the same 382 rgb-sum threshold gtk_color_map's on() uses, so Firefox and
    GTK agree about what 'on accent' means."""
    return p["background"] if rgb_sum(c) > 382 else p["bright_foreground"]


def firefox_colors(p: dict) -> dict:
    """The handful of derived surfaces every Firefox rule below is built from.

    Names mirror what the tokens call things (toolbox / toolbar / field / panel
    / tab) so the generated CSS reads like the file it is overriding. Shades
    come from the theme's own background/backgrounds keys when it ships them,
    else from the same mix() ramps the GTK pass uses."""
    bg, fg, accent = p["background"], p["foreground"], p["accent"]
    muted = p.get("muted") or fg
    surface = p.get("lighter_background") or mix(bg, fg, 0.06)
    deep = p.get("darker_background") or mix(bg, "#000000", 0.25)

    def shade(c: str, amount: float) -> str:
        # toward white on a dark theme, toward black on a light one — the
        # accent has to move away from the page in the same direction it sits
        return mix(c, "#ffffff", amount) if p["mode"] == "dark" else mix(c, "#000000", amount)

    tab_sel = mix(bg, accent, 0.45)
    return {
        "bg": bg, "fg": fg, "muted": muted, "accent": accent,
        "accent_hover": shade(accent, 0.15), "accent_active": shade(accent, 0.30),
        "on_accent": readable_on(accent, p),
        "surface": surface, "deep": deep,
        "border": mix(surface, fg, 0.35),
        "field": mix(bg, fg, 0.10), "field_focus": mix(bg, fg, 0.16),
        "panel": surface, "panel_border": mix(surface, fg, 0.35),
        "list_bg": mix(surface, fg, 0.12),
        "tab_sel": tab_sel, "tab_sel_fg": readable_on(tab_sel, p),
        "tab_hover": mix(bg, fg, 0.12), "hover": mix(surface, accent, 0.30),
        "alt_row": mix(bg, fg, 0.05), "list_hover": mix(bg, accent, 0.25),
        "mode": p["mode"],
    }


def firefox_chrome_css(p: dict) -> str:
    """userChrome.css — browser chrome (tab strip, toolbars, panels, sidebar).

    Firefox 157 colours itself from design-system *tokens*; the Proton names
    every userChrome theme used to override (--toolbar-bgcolor,
    --tab-selected-bgcolor, --arrowpanel-background) are gone, so this file
    targets the tokens that replaced them, verified against this build's own
    omni.ja. `!important` throughout: userChrome.css is a user-origin sheet and
    user !important beats the browser's author !important (layer order never
    gets a vote once origin+importance have sorted first)."""
    c = firefox_colors(p)
    sections = [
        ("accent — focus rings, hover mixes, selected everything", [
            ("color-accent-primary", c["accent"]),
            ("color-accent-primary-hover", c["accent_hover"]),
            ("color-accent-primary-active", c["accent_active"]),
            ("color-accent-primary-selected", c["accent"]),
            ("focus-outline-color", c["accent"]),
        ]),
        ("toolbox + toolbars — the box behind tabs and the nav bar", [
            ("toolbox-background-color", c["surface"]),
            ("toolbox-background-color-inactive", c["surface"]),
            ("toolbox-text-color", c["fg"]),
            ("toolbox-text-color-inactive", c["muted"]),
            ("toolbar-background-color", c["bg"]),
            ("toolbar-text-color", c["fg"]),
            ("toolbar-border", c["border"]),
            ("toolbarbutton-icon-fill", c["fg"]),
            ("toolbarbutton-background-color-hover", c["hover"]),
        ]),
        ("tabs", [
            ("tab-background-color-hover", c["tab_hover"]),
            ("tab-background-color-selected", c["tab_sel"]),
            ("tab-text-color", c["fg"]),
            ("tab-text-color-hover", c["fg"]),
            ("tab-text-color-selected", c["tab_sel_fg"]),
            ("tab-border-color", c["accent"]),
        ]),
        ("urlbar + toolbar fields", [
            ("toolbar-field-background-color", c["field"]),
            ("toolbar-field-background-color-focus", c["field_focus"]),
            ("toolbar-field-text-color", c["fg"]),
            ("toolbar-field-text-color-focus", c["fg"]),
            ("toolbar-field-border-color", c["border"]),
            ("urlbar-background-color", c["field"]),
            ("urlbar-background-color-focus", c["field_focus"]),
            ("urlbar-box-background-color", c["field_focus"]),
            ("input-text-background-color", c["field"]),
        ]),
        ("panels — hamburger menu, dropdowns, the urlbar result list", [
            ("panel-background-color", c["panel"]),
            ("panel-border-color", c["panel_border"]),
            ("panel-list-background-color", c["list_bg"]),
            ("panel-list-text-color", c["fg"]),
        ]),
        ("buttons", [
            ("button-background-color-primary", c["accent"]),
            ("button-background-color-primary-hover", c["accent_hover"]),
            ("button-background-color-primary-active", c["accent_active"]),
            ("button-background-color-primary-selected", c["accent"]),
            ("button-text-color-primary", c["on_accent"]),
        ]),
        ("sidebar", [
            ("sidebar-background-color", c["deep"]),
            ("sidebar-text-color", c["fg"]),
        ]),
        ("lwtheme plumbing — only read when an extension theme is installed", [
            ("lwt-accent-color", c["bg"]),
            ("lwt-text-color", c["fg"]),
        ]),
    ]

    lines = []
    for title, tokens in sections:
        lines.append(f"  /* {title} */")
        lines += [f"  --{name}: {value} !important;" for name, value in tokens]
        lines.append("")

    # Element-level safety net: a build that reads a token this file has not
    # heard of still paints the chrome box, the urlbar and the selected tab
    # with our colours instead of falling back to the system theme.
    net = f"""  /* safety net for anything the tokens above do not reach */
  #navigator-toolbox, #nav-bar {{
    background-color: {c['surface']} !important;
    color: {c['fg']} !important;
  }}
  #urlbar, #urlbar-input-container, #searchbar {{
    background-color: {c['field']} !important;
    color: {c['fg']} !important;
  }}
  .tabbrowser-tab[selected] .tab-background {{
    background-color: {c['tab_sel']} !important;
  }}"""

    return f"""/* quickshell theme: {THEME_DIR.name} (generated by global-theme.py — do not edit)
 *
 * Firefox 157+ palette, written as the design-system tokens the browser reads.
 * Restart Firefox to pick it up: Gecko loads these once at startup (user.js
 * prefs too), there is no live-reload hook the way kitty has `@ set-colors`.
 */
:root {{
  color-scheme: {c['mode']} !important;

{chr(10).join(lines).rstrip()}
{net}
}}
"""


def firefox_content_css(p: dict) -> str:
    """userContent.css — about: pages (preferences, config, new tab).

    Scoped with @-moz-document (a user-sheet-only at-rule) so none of these
    names can ever land on a website's :root; the properties are Mozilla's
    own, but color-scheme definitely is not something to impose on the web."""
    c = firefox_colors(p)
    tokens = [
        ("background-color-canvas", c["bg"]),
        ("background-color-box", c["surface"]),
        ("background-color-box-info", c["list_bg"]),
        ("background-color-list-item-hover", c["list_hover"]),
        ("table-row-background-color-alternate", c["alt_row"]),
        ("text-color", c["fg"]),
        ("text-color-deemphasized", c["muted"]),
        ("heading-text-color", c["accent"]),
        ("border-color", c["border"]),
        ("border-color-deemphasized", c["list_bg"]),
        ("color-accent-primary", c["accent"]),
        ("color-accent-primary-hover", c["accent_hover"]),
        ("color-accent-primary-active", c["accent_active"]),
        ("focus-outline-color", c["accent"]),
        ("link-color", c["accent"]),
        ("link-color-hover", c["accent_hover"]),
        ("link-color-active", c["accent_active"]),
        ("button-background-color-primary", c["accent"]),
        ("button-background-color-primary-hover", c["accent_hover"]),
        ("button-background-color-primary-active", c["accent_active"]),
        ("button-text-color-primary", c["on_accent"]),
    ]
    body = "\n".join(f"    --{name}: {value} !important;" for name, value in tokens)
    return f"""/* quickshell theme: {THEME_DIR.name} (generated by global-theme.py — do not edit)
 *
 * about: pages only — @-moz-document keeps this off every website's :root.
 */
@-moz-document url-prefix("about:"), url-prefix("chrome://") {{
  :root {{
    color-scheme: {c['mode']} !important;
{body}
  }}
}}
"""


def firefox_prefs(p: dict) -> dict:
    """user.js entries: turn the stylesheets on, and put the content colour
    scheme where the theme's mode says it goes (0 dark / 1 light / 2 system —
    verified against this build's ext-browserSettings.js)."""
    dark = p["mode"] == "dark"
    return {
        # off by default — without it Gecko silently ignores userChrome.css
        "toolkit.legacyUserProfileCustomizations.stylesheets": "true",
        # GTK normally feeds this one from the desktop; ours wins while it is
        # set and self-heals to GTK afterwards (Firefox clears it itself)
        "ui.systemUsesDarkTheme": "1" if dark else "0",
        "layout.css.prefers-color-scheme.content-override": "0" if dark else "1",
    }


def apply_firefox(p: dict):
    """Profile-level theming: userChrome.css + userContent.css carry the
    palette, user.js flips the stylesheet pref and the colour-scheme prefs.

    Chromium gets a live refresh (--refresh-platform-policy); Gecko has no
    equivalent, so a running browser keeps its old colours until the next
    start and we say so in the log instead of pretending otherwise."""
    if not FF_DIR.is_dir() and not shutil.which("firefox"):
        log("firefox", "not installed — skipping")
        return

    profile, hash_ = firefox_profile()
    if profile is None:
        if not firefox_needs_seed():
            log("firefox", "no profile this script understands — "
                           "launch Firefox once, then re-apply")
            return
        profile = seed_firefox_profile()
    elif not hash_ and not DRY and claim_firefox_install(profile):
        log("firefox profile", "claimed as default for install "
                               + FF_STATE.read_text(encoding="utf-8").strip())
    if hash_ and not FF_STATE.is_file() and not DRY:
        # remember what Firefox told us: a reinstall at another path rewrites
        # it, a fresh clone still has this machine's answer
        FF_STATE.parent.mkdir(parents=True, exist_ok=True)
        FF_STATE.write_text(hash_ + "\n", encoding="utf-8")

    write(profile / "chrome/userChrome.css", firefox_chrome_css(p))
    write(profile / "chrome/userContent.css", firefox_content_css(p))

    prefs = firefox_prefs(p)
    user_js = profile / "user.js"
    existing = user_js.read_text(encoding="utf-8") if user_js.is_file() else ""
    out, applied = [], set()
    for line in existing.splitlines():
        m = re.match(r'\s*user_pref\(\s*"([^"]+)"\s*,', line)
        if m and m.group(1) in prefs:
            if m.group(1) not in applied:
                out.append(f'user_pref("{m.group(1)}", {prefs[m.group(1)]});')
                applied.add(m.group(1))
        else:
            out.append(line)          # the user's own prefs are never touched
    for key, value in prefs.items():
        if key not in applied:
            out.append(f'user_pref("{key}", {value});')
    write(user_js, "\n".join(out) + "\n")

    running = subprocess.run(["pgrep", "-x", "firefox"], capture_output=True).returncode == 0
    note = " — restart Firefox to recolour" if running else ""
    log("firefox", f"{profile}{note}")


# ------------------------------------------------------ yaru folder colours ---

FOLDERS_NAME = "quickshell-folders"
FOLDERS_DIR = HOME / ".local/share/icons/quickshell-folders"
FOLDERS_STAMP = STATE / "folders.stamp"


def icon_theme_dir(name: str):
    """Directory of an installed icon theme — user themes first, since the
    overlay this builds lives there rather than in /usr/share/icons."""
    if not name:
        return None
    for root in (HOME / ".local/share/icons", pathlib.Path("/usr/share/icons")):
        d = root / name
        if (d / "index.theme").is_file():
            return d
    return None


def icon_theme_inherits(d: pathlib.Path) -> str:
    """First name out of the theme's Inherits= line (our own overlay, when it
    is the active theme, records its base there)."""
    try:
        for line in (d / "index.theme").read_text(encoding="utf-8").splitlines():
            if line.startswith("Inherits="):
                return line.split("=", 1)[1].split(",")[0].strip()
    except OSError:
        pass
    return ""


def current_icon_theme() -> str:
    """The icon theme the desktop is wearing right now — the same
    read-before-write dance as current_gtk_theme, because gsettings answers
    with a *default* for a key nobody ever set and that answer must not be
    mistaken for a choice."""
    session = bool(os.environ.get("DBUS_SESSION_BUS_ADDRESS"))
    if session and shutil.which("dconf"):
        r = subprocess.run(["dconf", "read", "/org/gnome/desktop/interface/icon-theme"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            val = r.stdout.strip().strip("'\"")
            if val:
                return val
    elif session and shutil.which("gsettings"):
        r = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            val = r.stdout.strip().strip("'\"")
            if val and val not in ("Adwaita", "Default"):
                return val
    return ""


def folder_base_theme(declared: str):
    """(name, dir) of the icon theme the folders get tinted on top of.

    The theme's own icons.theme wins, so every non-folder icon keeps exactly
    the Yaru variant that theme asked for and only `places/` changes hands.
    Failing that: whatever the desktop already wears, then the Yaru-blue/stock
    Yaru pair switch-theme has always fallen back to."""
    names = [declared, current_icon_theme(), FOLDERS_NAME, "Yaru-blue", "Yaru"]
    seen = set()
    for name in names:
        if not name or name in seen:
            continue
        seen.add(name)
        d = icon_theme_dir(name)
        if name == FOLDERS_NAME:
            # we are the active overlay already — rebase on the base it names
            name = icon_theme_inherits(d)
            if not name or name in seen:
                continue
            d = icon_theme_dir(name)
        if d:
            return name, d
    return "", None


def folder_icon_sources(base: pathlib.Path) -> dict:
    """rel path -> source png for every folder icon the base ships.

    Every context, not just places/: `actions/folder-new` and
    `status/folder-drag-accept` are folder drawings too and would otherwise
    keep the old colour next to the tinted ones. The only thing filtered is
    the name (folder* / inode-directory) and the format — Yaru draws folders
    as raster at every size, and the SVGs under places/ are the *-symbolic
    ones, which are meant to follow the text colour rather than the accent.
    Stock Yaru is the second root because variants ship only some of the sizes
    and inherit the rest from it."""
    roots = [base]
    yaru = pathlib.Path("/usr/share/icons/Yaru")
    if base != yaru:
        roots.append(yaru)
    sources = {}
    for root in roots:
        for src in sorted(root.glob("*/*/*.png")):
            if src.name.startswith("folder") or src.name == "inode-directory.png":
                sources.setdefault(src.relative_to(root).as_posix(), src)
    return sources


def dominant_color(path) -> tuple:
    """Most common opaque colour in an icon — Yaru's folder art is flat enough
    that this is the folder's actual fill (base Yaru: #da5b2a)."""
    im = Image.open(path).convert("RGBA")
    colors = im.getcolors(maxcolors=1_000_000) or []
    opaque = [(n, c[:3]) for n, c in colors if c[3] > 200]
    if not opaque:
        return None
    return max(opaque, key=lambda item: item[0])[1]


def tint_folder(src, dst, ref: tuple, target: tuple):
    """Recolour one folder PNG to `target`, keeping Yaru's own shading.

    Hue moves to the target; saturation and value scale by the
    target:source ratio so the dark edge stays the dark edge and a folder that
    ships a shade darker (folder-open) keeps that relationship. Pixels with
    almost no saturation are skipped — those are the highlights and the white
    paper on folder-documents, and dragging them along is what makes a naive
    hue shift look like a filter."""
    im = Image.open(src).convert("RGBA")
    alpha = im.getchannel("A")
    hue, sat, val = im.convert("RGB").convert("HSV").split()

    ref_h, ref_s, ref_v = colorsys.rgb_to_hsv(*(n / 255 for n in ref))
    tgt_h, tgt_s, tgt_v = colorsys.rgb_to_hsv(*(n / 255 for n in target))
    s_ratio = (tgt_s / ref_s) if ref_s > 0.05 else 1.0
    v_ratio = (tgt_v / ref_v) if ref_v > 0.05 else 1.0
    keep = sat.point(lambda x: 255 if x >= 32 else 0)

    hue2 = Image.composite(Image.new("L", im.size, round(tgt_h * 255)), hue, keep)
    sat2 = sat.point(lambda x: min(255, round(x * s_ratio)))
    val2 = Image.composite(val.point(lambda x: min(255, round(x * v_ratio))), val, keep)

    out = Image.merge("HSV", (hue2, sat2, val2)).convert("RGB").convert("RGBA")
    out.putalpha(alpha)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, "PNG")


def folders_index(base_name: str, rels) -> str:
    """index.theme for the overlay: inherits everything it does not ship, and
    declares only the dirs it actually contains — the entries are size/context
    paths (`48x48/places`), the same spelling Yaru uses, because GTK joins a
    Directories entry straight onto the theme dir and a bare `48x48` would
    point at a directory whose icons live one level deeper (they get ignored,
    and the whole tint silently falls back to the base)."""
    dirs = sorted({"/".join(rel.split("/")[:2]) for rel in rels if rel.count("/") >= 2})
    contexts = {"places": "Places", "actions": "Actions", "status": "Status"}
    lines = [
        "[Icon Theme]",
        "Name=Quickshell folders",
        f"Comment=Yaru folders tinted to the {THEME_DIR.name} accent",
        f"Inherits={base_name}",
        "Example=folder",
        "Directories=" + ",".join(dirs),
        "",
    ]
    for d in dirs:
        size_dir, context = d.split("/", 1)
        m = re.match(r"(\d+)x(\d+)(@2x)?", size_dir)
        if not m:
            continue
        lines += [f"[{d}]", f"Context={contexts.get(context, 'Places')}",
                  f"Size={m.group(1)}"]
        if m.group(3):
            lines.append("Scale=2")
        lines += ["Type=Fixed", ""]
    return "\n".join(lines) + "\n"


def apply_folders(p: dict, declared: str) -> str:
    """Build the accent-tinted folder overlay and return the icon theme name to
    apply — "" when it cannot run, so the caller falls back to the plain
    variant exactly as this script did before folders were a thing here.

    Yaru's colour variants (Yaru-sage, Yaru-magenta, …) differ only in folder
    colour, which means a theme's folders were tied to whichever variant its
    icons.theme named — or to a stale one when the theme named none. Deriving
    from the accent instead means every wallpaper-generated theme gets folders
    that match it, with Ubuntu's own folder art doing the drawing."""
    if Image is None:
        log("yaru folders", "Pillow missing — keeping the plain icon theme")
        return ""
    base_name, base_dir = folder_base_theme(declared)
    if base_dir is None:
        log("yaru folders", "no icon theme installed to tint folders from")
        return ""

    sources = folder_icon_sources(base_dir)
    if not sources:
        log("yaru folders", f"{base_name} ships no folder icons")
        return ""

    accent = p["accent"].lstrip("#")
    accent_rgb = tuple(int(accent[i:i + 2], 16) for i in (0, 2, 4))
    stamp = f"{base_name}\n{p['accent']}\n{THEME_DIR.name}\n"
    if FOLDERS_STAMP.is_file() and FOLDERS_STAMP.read_text(encoding="utf-8") == stamp \
            and icon_theme_dir(FOLDERS_NAME):
        log("yaru folders", f"{FOLDERS_NAME} already {p['accent']}")
        return FOLDERS_NAME

    ref_src = sources.get("48x48/places/folder.png") or next(iter(sources.values()))
    ref = dominant_color(ref_src)
    if ref is None:
        log("yaru folders", f"cannot sample {ref_src.name} — keeping plain folders")
        return ""

    if DRY:
        log("yaru folders", f"{len(sources)} icons -> {FOLDERS_NAME} "
                            f"(base {base_name}, ref #{''.join(f'{c:02x}' for c in ref)})")
        return FOLDERS_NAME

    # rebuilt from scratch every time: an icon-theme.cache or an orphaned file
    # from an earlier base would shadow the new art otherwise
    if FOLDERS_DIR.exists():
        shutil.rmtree(FOLDERS_DIR)
    FOLDERS_DIR.mkdir(parents=True, exist_ok=True)
    for rel, src in sources.items():
        tint_folder(src, FOLDERS_DIR / rel, ref, accent_rgb)
    (FOLDERS_DIR / "index.theme").write_text(
        folders_index(base_name, sources), encoding="utf-8")
    FOLDERS_STAMP.parent.mkdir(parents=True, exist_ok=True)
    FOLDERS_STAMP.write_text(stamp, encoding="utf-8")
    log("yaru folders", f"{len(sources)} icons tinted {p['accent']} (base {base_name})")
    return FOLDERS_NAME


# ----------------------------------------------------------------- gsettings --

def current_gtk_theme() -> str:
    """The GTK theme the user picked (nwg-look / gsettings), read before we
    overwrite anything — with a fallback, because a machine with no dconf
    history must keep the choice instead of dropping to stock Adwaita.

    Order: dconf (the live choice; empty when the key was never set), then
    gsettings when dconf isn't around, then the recorded state file.
    gsettings reports the *default* for an unset key rather than nothing,
    so its answer only counts when it isn't that default."""
    def record(val: str) -> str:
        """Remember the choice so the next bare-TTY run reproduces it."""
        GTK_STATE.parent.mkdir(parents=True, exist_ok=True)
        GTK_STATE.write_text(val + "\n")
        return val

    session = bool(os.environ.get("DBUS_SESSION_BUS_ADDRESS"))
    if session and shutil.which("dconf"):
        r = subprocess.run(
            ["dconf", "read", "/org/gnome/desktop/interface/gtk-theme"],
            capture_output=True, text=True,
        )
        if r.returncode == 0:
            val = r.stdout.strip().strip("'\"")
            if val:                       # set on purpose, stock included
                return record(val)
    elif session:
        r = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
            capture_output=True, text=True,
        )
        if r.returncode == 0:
            val = r.stdout.strip().strip("'\"")
            if val and val not in ("Adwaita", "Default"):
                return record(val)

    if GTK_STATE.is_file():
        val = GTK_STATE.read_text().strip()
        if val:
            return val
    return ""


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


def apply_gsettings(p: dict, icons: str, have_icons: bool):
    """omarchy-theme-set-gnome port: scheme + icons per theme; GTK theme =
    the user's sticky choice flipped to this theme's mode. `icons` is the
    folder-colour overlay when one was built, else the theme's plain variant —
    `have_icons` says whether either actually exists to be applied."""
    scheme = "prefer-light" if p["mode"] == "light" else "prefer-dark"

    gtk = gtk_theme_name(p, current_gtk_theme())

    gs("color-scheme", f"'{scheme}'")
    gs("gtk-theme", f"'{gtk}'")
    if have_icons:
        gs("icon-theme", f"'{icons}'")
    else:
        log("icon-theme", f"{icons} not installed yet — keeping current")
    return gtk, scheme


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

icons_file = THEME_DIR / "icons.theme"
declared_icons = icons_file.read_text().strip() if icons_file.is_file() else "Yaru-blue"
# folders first: the overlay has to exist before gsettings/settings.ini point
# at it, and both are told about it through the same `icons` name
folder_theme = apply_folders(p, declared_icons)
icons = folder_theme or declared_icons
have_icons = bool(folder_theme) or (icons_file.is_file() and icon_theme_dir(icons) is not None)
gtk, scheme = apply_gsettings(p, icons, have_icons)
apply_gtk_ini(gtk, scheme, icons, have_icons)
apply_xsettingsd(gtk, icons, have_icons)
apply_gtk3_css(p, gtk)
apply_gtk4_css(p, gtk)
apply_foot(p)
apply_kitty(p)
apply_chromium(p)
apply_firefox(p)
apply_hyprland(p, raw)
apply_btop(p)
apply_nvim(p)
log("done", "global theming applied")
