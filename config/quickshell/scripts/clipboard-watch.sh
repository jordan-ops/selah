#!/bin/bash
# Clipboard capture for quickshell's native clipboard manager.
#
# Run by `wl-paste --watch <this>`: every new selection arrives byte-exact
# on stdin (verified: --watch does NOT append a newline, and it fires ONCE
# at start with whatever is currently offered — so a shell restart replays
# the live clipboard into history for free, deduped by the hash below).
#
# One append-only line per accepted entry:
#   ts_ms \t path \t sha256 \t mime \t size \t preview
# The Clipboard service watches that index with FileView — the index IS
# the persistence across restarts. flock keeps a single writer when a
# capture races clipboard-ctl.sh.

dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/clipboard"
entries="$dir/entries"
index="$dir/index"
mkdir -p "$entries"
umask 077

exec 9>"$dir/.lock"
flock 9 || exit 0

ts=$(($(date +%s%N) / 1000000))
tmp="$entries/.in.$ts"
cat > "$tmp" || { rm -f "$tmp"; exit 0; }

# empty selection (watch fires with empty stdin too) — drop it
[ -s "$tmp" ] || { rm -f "$tmp"; exit 0; }

# exact-byte dedupe: re-copies and the per-restart replay add nothing new
hash=$(sha256sum "$tmp" | cut -d' ' -f1)
if [ -f "$index" ] && cut -f3 "$index" | grep -qFx "$hash"; then
    rm -f "$tmp"
    exit 0
fi

# mime from the live offer (proxy for what the watch pipe chose)
mime=$(wl-paste --list-types 2>/dev/null | sed -n '1p')
mime=$(printf '%s' "$mime" | tr -d '\t\n\r')
[ -n "$mime" ] || mime="application/octet-stream"

# sniff the actual bytes for the extension — an app can offer image/png
# alongside text/uri-list, and the pipe may hand us either
sig=$(od -An -N4 -tx1 "$tmp" | tr -d ' \n')
case "$sig" in
    89504e47) ext=png ;;
    ffd8ff*)  ext=jpg ;;
    52494646)  # RIFF....WEBP?
        if [ "$(od -An -N4 -j8 -tx1 "$tmp" | tr -d ' \n')" = "57454250" ]; then ext=webp; else ext=bin; fi ;;
    *)  if LC_ALL=C grep -qI . "$tmp" 2>/dev/null; then ext=txt; else ext=bin; fi ;;
esac
# text gets a canonical type so the service's copy-back can branch on it
[ "$ext" = txt ] && mime="text/plain"

size=$(wc -c < "$tmp")
preview=""
if [ "$ext" = txt ]; then
    # tabs/newlines become spaces so the index stays one line per entry;
    # byte cap keeps huge clips from bloating the file (search covers the
    # first ~1.2KB, which is where every real snippet lives anyway)
    preview=$(LC_ALL=C head -c 1200 "$tmp" | tr '\n\r\t' '   ')
fi

final="$entries/$ts.$ext"
mv "$tmp" "$final"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "$final" "$hash" "$mime" "$size" "$preview" >> "$index"

# cap at 100: drop the oldest lines together with their entry files
count=$(wc -l < "$index")
if [ "$count" -gt 100 ]; then
    drop=$((count - 100))
    head -n "$drop" "$index" | cut -f2 | while IFS= read -r f; do rm -f "$f"; done
    tail -n 100 "$index" > "$index.tmp"
    # in-place (cat >, never mv) so FileView's inotify watch survives —
    # same lesson as settings.json/colors.json
    cat "$index.tmp" > "$index"
    rm -f "$index.tmp"
fi
