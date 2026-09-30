#!/bin/sh
# set-text-size.sh <px> — the SIZE half of set-font.sh: one number for
# every mechanism that renders text on this machine, every family left
# exactly as picked:
#
#   gsettings  font-name / document-font-name / monospace-font-name
#              ("<family> <px>", each key keeps ITS family; falls back
#              to set-font.sh's state file when dconf is unavailable)
#   GTK3       gtk-3.0/settings.ini gtk-font-name (first-touch .bak)
#   kitty      kitty.conf font_size (first-touch .bak, SIGUSR1 reloads
#              every running instance — omarchy-font-set's nudge)
#   foot       foot.ini font= in fontconfig syntax family:size=, patched
#              in place or added as a leading key (valid main-section
#              position), validated with foot --check-config and rolled
#              back on failure — the fc-match rule, foot edition
#
# Safe-write rules from omasettings: hand-written files get a
# first-touch .bak and are edited ONE value at a time. No fc-cache —
# size is not a cacheable property. Range matches the settings row.
set -u

SIZE="${1:-}"
case "$SIZE" in
  ''|*[!0-9]*) echo "Usage: set-text-size.sh <9-20>" >&2; exit 1 ;;
esac
[ "$SIZE" -ge 9 ] && [ "$SIZE" -le 20 ] || {
  echo "size out of range (9-20): $SIZE" >&2; exit 1
}

STATE_DIR="$HOME/.local/state/quickshell"

# the family a gsettings key already holds, trailing size stripped:
# "'Mononoki Nerd Font Mono 11'" -> "Mononoki Nerd Font Mono"
get_family() {
  v=$(gsettings get "$1" "$2" 2>/dev/null) || return 1
  v=$(printf '%s' "$v" | sed -e "s/^['\"]//" -e "s/['\"]\$//" -e 's/[[:space:]][0-9]\+$//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# ---- GTK + GNOME apps: three keys, each keeps ITS family ----
FAM=$(get_family org.gnome.desktop.interface font-name) \
  || FAM=$(cat "$STATE_DIR/current-font" 2>/dev/null) || FAM=""
for key in font-name document-font-name monospace-font-name; do
  f=$(get_family org.gnome.desktop.interface "$key") || f="$FAM"
  [ -n "$f" ] || continue
  gsettings set org.gnome.desktop.interface "$key" "$f $SIZE" >/dev/null 2>&1 || true
done

# ---- GTK3 settings.ini — size only, family stays as written ----
INI="$HOME/.config/gtk-3.0/settings.ini"
if [ -f "$INI" ]; then
  [ -f "$INI.bak" ] || cp -p "$INI" "$INI.bak"
  gf=$(grep -m1 '^gtk-font-name=' "$INI" | cut -d= -f2- \
       | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
             -e "s/['\"]//g" -e 's/[[:space:]][0-9]\+$//')
  [ -n "$gf" ] || gf="$FAM"
  [ -n "$gf" ] || gf="Sans"
  if grep -q '^gtk-font-name=' "$INI"; then
    sed -i "s|^gtk-font-name=.*|gtk-font-name=$gf $SIZE|" "$INI"
  else
    printf 'gtk-font-name=%s %s\n' "$gf" "$SIZE" >> "$INI"
  fi
fi

# ---- kitty — size only, family stays; SIGUSR1 reloads running ones ----
KITTY="$HOME/.config/kitty/kitty.conf"
if [ -f "$KITTY" ]; then
  [ -f "$KITTY.bak" ] || cp -p "$KITTY" "$KITTY.bak"
  if grep -qE '^[[:space:]]*font_size[[:space:]]+' "$KITTY"; then
    sed -i -E "s/^[[:space:]]*font_size[[:space:]].*/font_size $SIZE/" "$KITTY"
  else
    printf '\nfont_size %s\n' "$SIZE" >> "$KITTY"
  fi
  pkill -USR1 kitty 2>/dev/null || true
fi

# ---- foot — font= is fontconfig syntax (family:size=NN). Leading keys
# before the first section header ARE the main section (check-config
# verified); a font= inside [colors-*] would be an invalid option, so an
# absent line goes to the TOP, never to the end of the file ----
FOOT="$HOME/.config/foot/foot.ini"
if [ -f "$FOOT" ]; then
  [ -f "$FOOT.bak" ] || cp -p "$FOOT" "$FOOT.bak"
  if grep -qE '^[[:space:]]*font=' "$FOOT"; then
    if grep -qE '^[[:space:]]*font=.*:size=' "$FOOT"; then
      sed -i -E "s|:size=[0-9.]+|:size=$SIZE|g" "$FOOT"
    else
      sed -i -E "s|^([[:space:]]*font=.*)$|\1:size=$SIZE|" "$FOOT"
    fi
  else
    printf 'font=monospace:size=%s\n\n' "$SIZE" | cat - "$FOOT" > "$FOOT.tmp" \
      && mv "$FOOT.tmp" "$FOOT"
  fi
  # validate the whole config the way set-font.sh validates fonts.conf —
  # a broken foot.ini is the terminal refusing to start
  if command -v foot >/dev/null 2>&1; then
    if ! foot --config="$FOOT" --check-config >/dev/null 2>&1; then
      if [ -f "$FOOT.bak" ]; then cp -p "$FOOT.bak" "$FOOT"; else rm -f "$FOOT"; fi
      echo "foot.ini write failed validation; rolled back" >&2
    fi
  fi
fi

# remember what we set — SettingsTextSizeRow reads gsettings first, this
# is the fallback for a session where dconf is unavailable
mkdir -p "$STATE_DIR"
printf '%s' "$SIZE" > "$STATE_DIR/text-size"
exit 0
