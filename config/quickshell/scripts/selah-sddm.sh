#!/bin/bash
# selah-sddm — the Selah SDDM greeter: stage, activate, sync.
#
# Three layers:
#   * staged theme  ~/.local/share/sddm/themes/selah   (user-owned source
#     of truth: Main.qml, logo, generated wallpaper + palette)
#   * installed     /usr/share/sddm/themes/selah       (root copy, what the
#     greeter actually loads)
#   * activation    /etc/sddm.conf.d/selah.conf        ([Theme] Current=<name>)
#
# The two root operations (install / set) run through the root-owned copy
# at /usr/local/sbin/selah-sddm, which the one-time `setup-help` command
# installs together with a NOPASSWD sudoers drop-in. Without that setup
# they degrade to a clear hint + exit 1 — never a fake success and never
# an interactive password prompt (quickshell has no terminal for one).
#
# --dry-run prints instead of writing, so everything is testable as a
# plain user.
set -u

ROOT_SVC=/usr/local/sbin/selah-sddm
CONF_DIR=/etc/sddm.conf.d
CONF=$CONF_DIR/selah.conf
SYS=/usr/share/sddm/themes/selah

# The staged theme and its state belong to the invoking user's home — even
# when we run as root via `sudo -n $ROOT_SVC …` (where $HOME=/root). Both
# resolve at runtime, so a clone under any username works unchanged.
if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
    STAGE_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    STAGE_HOME=${HOME:-}
fi
# Last resort when HOME is unset (bare root shell): ask the passwd db.
STAGE_HOME=${STAGE_HOME:-$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)}
if [ -z "$STAGE_HOME" ]; then
    echo "selah-sddm: cannot resolve the invoking user's home directory" >&2
    exit 1
fi
STAGE=$STAGE_HOME/.local/share/sddm/themes/selah
STATE=$STAGE_HOME/.local/state/quickshell

SELF=$(readlink -f "$0")
DRY=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY=1
    shift
fi
cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi

usage() {
    cat <<EOF
selah-sddm — Selah SDDM greeter: stage, activate, sync.

Usage: selah-sddm.sh [--dry-run] <command>

  current        print the active SDDM theme (or "default")
  sync           copy the current wallpaper + colors.json palette into the
                 staged theme, then refresh the installed copy if root
                 allows it (user-level, safe to run any time)
  set <name>     activate a theme (selah | elarun | maldives | maya);
                 selah also installs the staged theme first   [root]
  install        copy the staged theme to /usr/share/sddm/themes [root]
  setup-help     print the one-time sudo setup commands
  _refresh       re-copy staged assets over the installed theme  [root]

Root commands run through $ROOT_SVC (created by setup-help). With
--dry-run every command prints what it would do instead of doing it.
EOF
}

# --- root escalation ------------------------------------------------------
# As root: run directly. Otherwise re-exec the root-owned helper with sudo -n
# (NOPASSWD drop-in from setup-help). A missing setup is an error with a
# pointer, never a hang on a password prompt we can't answer.
escalate() {
    if [ "$DRY" -eq 1 ]; then
        echo "[dry-run] sudo $ROOT_SVC $*"
        return 0
    fi
    if [ ! -x "$ROOT_SVC" ]; then
        echo "selah-sddm: root helper not installed — run: $SELF setup-help" >&2
        return 1
    fi
    local out rc
    out=$(sudo -n "$ROOT_SVC" "$@" 2>&1)
    rc=$?
    [ -n "$out" ] && printf '%s\n' "$out"
    if [ $rc -ne 0 ]; then
        if printf '%s' "$out" | grep -qi 'password is required'; then
            echo "selah-sddm: sudo needs a password (NOPASSWD drop-in missing) — run: $SELF setup-help" >&2
        else
            echo "selah-sddm: root step failed — setup hint: $SELF setup-help" >&2
        fi
    fi
    return $rc
}

# --- commands -------------------------------------------------------------
current_cmd() {
    # /etc/sddm.conf first, then conf.d drop-ins in glob order: the last
    # Current= wins, which is also how SDDM merges them.
    local f v got
    v=""
    for f in /etc/sddm.conf "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        got=$(sed -n 's/^[[:space:]]*Current[[:space:]]*=[[:space:]]*//p' "$f" | head -n1 | tr -d '[:space:]"'"'"'')
        [ -n "$got" ] && v=$got
    done
    printf '%s\n' "${v:-default}"
}

sync_cmd() {
    if [ ! -d "$STAGE" ]; then
        echo "selah-sddm: no staged theme at $STAGE — run: $SELF install" >&2
        return 1
    fi
    local assets="$STAGE/assets"
    mkdir -p "$assets"

    # 1) wallpaper — fixed name on purpose: Qt's image loader sniffs the
    #    real format from the bytes, so .png name + .jpg payload is fine.
    local wp=""
    [ -f "$STATE/current-wallpaper" ] && wp=$(cat "$STATE/current-wallpaper")
    if [ -n "$wp" ] && [ -f "$wp" ]; then
        cp -f "$wp" "$assets/background.png" && chmod 644 "$assets/background.png"
    else
        echo "selah-sddm: no current wallpaper found — keeping existing background" >&2
    fi

    # 2) palette → assets/vars.js (greeter imports it as V.*). Regenerated
    #    whole via tmp+mv; nothing watches this file, so mv is safe.
    local colors="$STATE/generated/colors.json"
    if [ -f "$colors" ]; then
        local tmp="$assets/vars.js.tmp" k fb v
        {
            echo "// Generated by selah-sddm.sh sync from colors.json — do not edit."
            echo "// Main.qml imports this file as V (wallpaper-dimming palette)."
            for spec in "background:#1e1e2e" "surface_variant:#161622" \
                        "secondary_container:#313244" "primary:#89b4fa" \
                        "on_background:#cdd6f4" "on_surface_variant:#585b70" \
                        "error:#f38ba8" "outline:#45475a"; do
                k=${spec%%:*}
                fb=${spec##*:}
                v=$(grep -oE "\"$k\": \"#[0-9a-fA-F]{6}\"" "$colors" | head -n1 | grep -oE '#[0-9a-fA-F]{6}')
                printf 'var %s = "%s";\n' "$k" "${v:-$fb}"
            done
        } > "$tmp" && mv -f "$tmp" "$assets/vars.js" && chmod 644 "$assets/vars.js"
    else
        echo "selah-sddm: no colors.json yet — keeping existing palette" >&2
    fi

    # 3) installed copy follows along silently, once the root helper exists
    if [ -x "$ROOT_SVC" ]; then
        sudo -n "$ROOT_SVC" _refresh >/dev/null 2>&1 || true
    fi
    echo "synced greeter theme (staged)"
}

install_theme() {
    if [ ! -d "$STAGE" ]; then
        echo "selah-sddm: no staged theme at $STAGE" >&2
        return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "[dry-run] would install $STAGE -> $SYS (chmod a+rX)"
        return 0
    fi
    mkdir -p "$(dirname "$SYS")"
    rm -rf "$SYS"
    cp -a "$STAGE" "$SYS"
    chmod -R a+rX "$SYS"    # sddm user must be able to read everything
    echo "installed $SYS"
}

set_theme() {
    local name="${1:-}"
    case "$name" in
        selah|elarun|maldives|maya) ;;
        "") echo "usage: selah-sddm.sh set <selah|elarun|maldives|maya>" >&2; return 1 ;;
        *)  echo "selah-sddm: unknown theme '$name' (expected: selah, elarun, maldives, maya)" >&2; return 1 ;;
    esac
    if [ "$name" = selah ]; then
        install_theme || return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "[dry-run] would write [Theme] Current=$name to $CONF"
        return 0
    fi
    mkdir -p "$CONF_DIR"
    # SDDM parses drop-ins as INI: the key must sit under [Theme] or the
    # daemon never sees it (its own vendor default.conf shows the shape).
    printf '# Written by selah-sddm (quickshell settings app) — safe to delete.\n[Theme]\nCurrent=%s\n' \
        "$name" > "$CONF"
    chmod 644 "$CONF"
    echo "Current=$name"
}

refresh_installed() {
    [ -d "$SYS" ] || return 0    # not installed yet — nothing to refresh
    [ -d "$STAGE" ] || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "[dry-run] would refresh $SYS/assets from $STAGE/assets"
        return 0
    fi
    cp -rf "$STAGE/assets" "$SYS/"
    chmod -R a+rX "$SYS"
    echo "refreshed $SYS"
}

setup_help() {
    cat <<EOF
One-time root setup for SDDM theme switching — paste into a terminal:

  sudo install -Dm755 $SELF $ROOT_SVC
  echo '$USER ALL=(root) NOPASSWD:$ROOT_SVC' | sudo tee /etc/sudoers.d/selah-sddm

After that, theme chips in the settings app apply instantly (no password).
EOF
}

# --- dispatch -------------------------------------------------------------
# as root through `sudo -n $ROOT_SVC`: the installed copy is a snapshot of
# this user copy (setup-help installs it once) — refresh it in place when
# it has drifted, so a script edit can't sit invisible in the user copy
# while `set` keeps re-running old root logic (bit us: a conf-format fix
# lived only here). Same-dir tmp + mv keeps THIS invocation's inode stable;
# exec once (flag breaks the loop if mv ever failed) so the refresh lands
# on this run too.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] \
        && [ "${SELAH_REFRESHED:-}" != 1 ]; then
    _src="$STAGE_HOME/.config/quickshell/scripts/selah-sddm.sh"
    if [ -f "$_src" ] && ! cmp -s "$_src" "$ROOT_SVC" \
            && bash -n "$_src" 2>/dev/null; then
        if cp -f "$_src" "$ROOT_SVC.new" 2>/dev/null \
                && chmod 755 "$ROOT_SVC.new" 2>/dev/null \
                && mv -f "$ROOT_SVC.new" "$ROOT_SVC" 2>/dev/null; then
            export SELAH_REFRESHED=1
            exec "$ROOT_SVC" "$@"
        fi
    fi
fi
unset _src

case "$cmd" in
    current)      current_cmd ;;
    sync)         sync_cmd ;;
    install|set|_refresh)
        # dry-run never escalates: run the function locally so argument
        # validation still happens, with every write replaced by a print
        if [ "$(id -u)" -ne 0 ] && [ "$DRY" -eq 0 ]; then
            escalate "$cmd" "$@"
            exit $?
        fi
        case "$cmd" in
            install)   install_theme ;;
            set)       set_theme "${1:-}" ;;
            _refresh)  refresh_installed ;;
        esac
        ;;
    setup-help)   setup_help ;;
    ""|-h|--help) usage ;;
    *)            echo "selah-sddm: unknown command '$cmd'" >&2; usage >&2; exit 2 ;;
esac
