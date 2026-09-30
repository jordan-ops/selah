#!/usr/bin/env bash
#
# install.sh — build this desktop from a clone of the repo.
#
#   ./install.sh              configs, wallpapers, fonts, active theme (no sudo)
#   ./install.sh --apps       ... plus every package, each installed --needed
#   ./install.sh --dry-run    print what would happen and change nothing
#   ./install.sh --skip-nvim   leave astro (lazy) plugin sync out of it
#   ./install.sh --help
#
# HOW IT WORKS
#   Everything ends up as a symlink pointing back into this repo, so git is
#   the single source of truth: `git pull` updates the desktop, and an edit
#   made in ~/.config is an edit made here, ready to commit.
#
#       ln -s  ~/.dotfiles/config/quickshell  ~/.config/quickshell
#
#   A path that already exists is never overwritten in place — it is MOVED to
#   ~/.dotfiles-backups/<timestamp>/ first, so a re-run is always recoverable
#   and an old hand-made config is never thrown away.
#
#   Re-running is safe: correctly-linked paths are skipped, missing state files
#   are the only ones seeded, and your current font is left alone if you have
#   one already.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP="$HOME/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)"

DO_APPS=0
DO_LINKS=1
DO_NVM=1
DRY=0
LINKED=0
BACKED=0

usage() {
    cat <<'EOF'
install.sh — build this desktop from a clone of the repo.

  ./install.sh              configs, wallpapers, fonts, active theme (no sudo)
  ./install.sh --apps       ... plus every package, each installed with --needed
  ./install.sh --dry-run    print what would happen and change nothing
  ./install.sh --skip-nvim  skip astro (lazy) plugin sync
  ./help is here, not a separate file:  ./install.sh --help

Packages come from packages/official.txt (pacman), packages/aur.txt (yay) and
packages/fonts.txt (tried against the official repos first, yay second). Lines
starting with # and blank lines are ignored, so lists can carry notes.
EOF
    exit 0
}

head1() { printf '\n==> %s\n' "$*"; }
note()  { printf '    %s\n' "$*"; }
dry()   { printf '    DRY  %s\n' "$*"; }

# run <cmd...> — the single door through which anything state-changing goes,
# so --dry-run can describe the whole install without doing a byte of it.
run() {
    if [ "$DRY" = 1 ]; then dry "$*"; else "$@"; fi
}

# read_list <file> — package names with comments and blanks stripped.
read_list() {
    [ -f "$1" ] || return 0
    grep -hvE '^[[:space:]]*(#|$)' "$1" || true
}

# link_one <src> <dest> — dest becomes a symlink to src. Anything already at
# dest moves into the backup tree first (its path is preserved under
# ~/.dotfiles-backups/<stamp>/ so several runs never collide).
link_one() {
    local src="$1" dest="$2" rel
    if [ ! -e "$src" ]; then
        note "no source for $dest — skipped"
        return 0
    fi
    # already the right arrow: nothing to do, and nothing to churn
    if [ -L "$dest" ] && [ "$(readlink -f -- "$dest")" = "$(readlink -f -- "$src")" ]; then
        return 0
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        rel="${dest#"$HOME"/}"
        if [ "$DRY" = 1 ]; then
            dry "backup $rel"
        else
            mkdir -p -- "$BACKUP/$(dirname -- "$rel")"
            mv -- "$dest" "$BACKUP/$rel"
            note "backed up $rel"
        fi
        BACKED=$((BACKED + 1))
    fi
    if [ "$DRY" = 1 ]; then
        dry "link   ${dest#"$HOME"/} -> ${src#"$HOME"/}"
    else
        mkdir -p -- "$(dirname -- "$dest")"
        ln -s -- "$src" "$dest"
    fi
    LINKED=$((LINKED + 1))
}

install_packages() {
    head1 "Packages (every one passed --needed)"
    local pkgs=() fonts=() off_fonts=() aur_fonts=() p

    if ! command -v sudo >/dev/null 2>&1; then
        note "no sudo on this system — skipping package installation"
        return 0
    fi

    mapfile -t pkgs < <(read_list "$REPO/packages/official.txt")
    if [ "${#pkgs[@]}" -gt 0 ]; then
        note "pacman: ${#pkgs[@]} packages in packages/official.txt"
        run sudo pacman -S --needed "${pkgs[@]}"
    fi

    if ! command -v yay >/dev/null 2>&1; then
        note "yay missing — bootstrapping from the AUR"
        run sudo pacman -S --needed git base-devel
        if [ "$DRY" = 1 ]; then
            dry "build yay-bin from https://aur.archlinux.org/yay-bin"
        else
            local tmp
            tmp="$(mktemp -d)"
            git clone -q https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
            (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
            rm -rf "$tmp"
        fi
    fi

    mapfile -t pkgs < <(read_list "$REPO/packages/aur.txt")
    if [ "${#pkgs[@]}" -gt 0 ] && command -v yay >/dev/null 2>&1; then
        note "yay: ${#pkgs[@]} packages in packages/aur.txt"
        note "(these are your machine's AUR set — nvidia-470xx-dkms and the"
        note " *-debug entries are specific to it; edit the list for other HW)"
        run yay -S --needed "${pkgs[@]}"
    fi

    # fonts: one list, routed by whether the official repos know the name
    mapfile -t fonts < <(read_list "$REPO/packages/fonts.txt")
    for p in "${fonts[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then off_fonts+=("$p"); else aur_fonts+=("$p"); fi
    done
    if [ "${#off_fonts[@]}" -gt 0 ]; then
        note "fonts from the official repos: ${#off_fonts[@]}"
        run sudo pacman -S --needed "${off_fonts[@]}"
    fi
    if [ "${#aur_fonts[@]}" -gt 0 ] && command -v yay >/dev/null 2>&1; then
        note "fonts from the AUR: ${#aur_fonts[@]}"
        run yay -S --needed "${aur_fonts[@]}"
    fi
}

# Boot services. A fresh Arch install leaves these PRESET-DISABLED, so a
# clone of the repo would otherwise land at a TTY with no login manager.
# Only `enable` — nothing is started mid-install, so on a machine you are
# sitting at this changes nothing that is already running.
enable_services() {
    head1 "Boot services (enabled for next login, nothing started now)"
    local svcs=() s
    if ! command -v systemctl >/dev/null 2>&1; then
        note "no systemctl — skipping"
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        note "no sudo — skipping"
        return 0
    fi
    mapfile -t svcs < <(read_list "$REPO/packages/services.txt")
    if [ "${#svcs[@]}" -eq 0 ]; then
        note "packages/services.txt is empty — nothing to enable"
        return 0
    fi
    for s in "${svcs[@]}"; do
        if [ "$DRY" = 1 ]; then
            dry "systemctl enable $s"
        elif sudo systemctl enable "$s" >/dev/null 2>&1; then
            note "enabled $s"
        else
            note "could not enable $s — run: sudo systemctl enable $s"
        fi
    done
}

link_configs() {
    head1 "Config symlinks"
    local d
    for d in "$REPO"/config/*; do
        [ -d "$d" ] || continue
        link_one "$d" "$HOME/.config/$(basename "$d")"
    done

    head1 "Personal scripts"
    for d in "$REPO"/local/bin/*; do
        [ -e "$d" ] || continue
        link_one "$d" "$HOME/.local/bin/$(basename "$d")"
    done
    note "~/.local/bin is deliberately not on PATH — binds call these by full path."

    # local/share carries the SDDM greeter's staged theme — linked the same
    # way so the login screen ships with the repo instead of living in one
    # home directory. (wayland-session.log lands here too: gitignored.)
    for d in "$REPO"/local/share/*; do
        [ -e "$d" ] || continue
        link_one "$d" "$HOME/.local/share/$(basename "$d")"
    done

    head1 "Wallpapers"
    run mkdir -p "$HOME/Wallpapers"
    for d in "$REPO"/wallpapers/*; do
        [ -e "$d" ] || continue
        link_one "$d" "$HOME/Wallpapers/$(basename "$d")"
    done
    # the theme--name.jpg symlinks are derived, so they get rebuilt here
    # rather than shipped (they point at absolute paths in ~/.config/themes)
    if [ -f "$REPO/config/quickshell/scripts/seed-wallpapers.sh" ]; then
        run bash "$REPO/config/quickshell/scripts/seed-wallpapers.sh" || true
    fi
}

seed_state() {
    head1 "State seeds (only files that don't exist yet)"
    local f dest
    run mkdir -p "$HOME/.local/state/quickshell"
    for f in "$REPO"/state/quickshell/*; do
        [ -e "$f" ] || continue
        dest="$HOME/.local/state/quickshell/$(basename "$f")"
        if [ -e "$dest" ]; then
            note "kept $(basename "$f") (already set on this machine)"
            continue
        fi
        if [ "$DRY" = 1 ]; then
            dry "seed   state/quickshell/$(basename "$f")"
        else
            cp -a -- "$f" "$dest"
            note "seeded $(basename "$f")"
        fi
    done
}

# Appearance (fontconfig + gsettings + kitty) is generated by set-font.sh, so
# it only gets rewritten when it is missing — re-running install.sh must not
# stomp a font you chose after the first install.
restore_appearance() {
    head1 "Appearance"
    local scripts="$REPO/config/quickshell/scripts"
    local fam size

    if [ -e "$HOME/.config/fontconfig/fonts.conf" ]; then
        note "fonts.conf present — leaving your current font alone"
    else
        fam="$(cat "$REPO/state/quickshell/current-font" 2>/dev/null || true)"
        if [ -z "$fam" ]; then
            note "no current-font recorded — skipping"
        elif fc-list 2>/dev/null | grep -Fqi -- "$fam"; then
            run bash "$scripts/set-font.sh" "$fam" || note "set-font.sh failed"
        else
            note "font '$fam' not installed yet — run with --apps, then re-run"
        fi
    fi

    if [ ! -e "$HOME/.local/state/quickshell/text-size" ] && [ -f "$scripts/set-text-size.sh" ]; then
        size="$(cat "$REPO/state/quickshell/text-size" 2>/dev/null || true)"
        [ -n "$size" ] && run bash "$scripts/set-text-size.sh" "$size" || true
    fi
}

apply_theme() {
    head1 "Active theme"
    local theme sh
    theme="$(cat "$REPO/state/quickshell/current-theme" 2>/dev/null || true)"
    if [ -z "$theme" ]; then
        note "no active theme recorded — skipping"
        return 0
    fi
    if [ ! -d "$HOME/.config/themes/$theme" ]; then
        note "theme '$theme' not present — skipping"
        return 0
    fi
    sh="$REPO/config/quickshell/scripts/switch-theme.sh"
    note "$theme — regenerates hypr/kitty/GTK/shell colours + wallpaper"
    run bash "$sh" "$theme" || note "switch-theme.sh failed (continuing)"
}

# SDDM greeter: the staged theme is linked from local/share/ above, but the
# root copy (/usr/share/sddm/themes) and the /etc drop-in need sudo. Runs
# only with --apps; the desktop itself doesn't depend on it — without it you
# get Arch's stock greeter, and nothing restarts, so it's safe anywhere.
install_greeter() {
    [ "$DO_APPS" = 1 ] || return 0
    local sh="$REPO/config/quickshell/scripts/selah-sddm.sh"
    [ -f "$sh" ] || return 0
    [ -d "$HOME/.local/share/sddm/themes/selah" ] || return 0
    command -v sudo >/dev/null 2>&1 || return 0
    head1 "SDDM greeter"
    if [ "$DRY" = 1 ]; then
        dry "sudo bash selah-sddm.sh set selah   (root copy + /etc/sddm.conf.d/selah.conf)"
    elif sudo bash "$sh" set selah >/dev/null 2>&1; then
        note "installed and set to 'selah' (live at next boot)"
    else
        note "could not install — run when you have sudo:"
        note "  sudo bash ${sh/#$HOME/~} set selah"
    fi
}

sync_nvim() {
    [ "$DO_NVM" = 1 ] || return 0
    command -v nvim >/dev/null 2>&1 || return 0
    if pgrep -x nvim >/dev/null 2>&1; then
        note "nvim is running — skip plugin sync (re-run later)"
        return 0
    fi
    head1 "AstroVim plugins"
    run timeout 900 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 \
        || note "plugin sync failed — open nvim once and run :Lazy sync"
}

# ---------------------------------------------------------------- arguments
for arg in "$@"; do
    case "$arg" in
        --apps)     DO_APPS=1 ;;
        --links)    DO_LINKS=1 ;;
        --no-links) DO_LINKS=0 ;;
        --dry-run)  DRY=1 ;;
        --skip-nvim) DO_NVM=0 ;;
        -h|--help)  usage ;;
        *) printf 'unknown option: %s (try --help)\n' "$arg" >&2; exit 2 ;;
    esac
done

head1 "dotfiles install"
note "repo   ${REPO/#$HOME/~}"
note "backup ${BACKUP/#$HOME/~}"
[ "$DRY" = 1 ] && note "DRY RUN — nothing will be changed"

[ "$DO_APPS" = 1 ] && { install_packages; enable_services; }
[ "$DO_LINKS" = 1 ] && { link_configs; seed_state; }
restore_appearance
apply_theme
install_greeter
sync_nvim

head1 "Done"
note "linked $LINKED path(s), backed up $BACKED to ${BACKUP/#$HOME/~}"
[ "$DRY" = 1 ] && note "dry run: re-run without --dry-run to apply"
command -v hyprctl >/dev/null 2>&1 && run hyprctl reload || true
note "bar not running? it starts with the session (autostart.lua runs \`qs\`)"
