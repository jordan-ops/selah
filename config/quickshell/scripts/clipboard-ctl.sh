#!/bin/bash
# Structural mutations of the clipboard index — same flock as
# clipboard-watch.sh, so a click-to-delete or clear-all can never
# interleave with a capture mid-append.
#
#   clipboard-ctl.sh remove <path>   drop one entry (line + file)
#   clipboard-ctl.sh clear           wipe history and every entry file

dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/clipboard"
index="$dir/index"
entries="$dir/entries"

exec 9>"$dir/.lock"
# bounded like clipboard-watch.sh — a stuck capture must not hang a click
flock -w 5 9 || exit 1

case "$1" in
    remove)
        [ -n "$2" ] || exit 1
        if [ -f "$index" ]; then
            awk -F'\t' -v p="$2" '$2 != p' "$index" > "$index.tmp" \
                && cat "$index.tmp" > "$index" && rm -f "$index.tmp"
        fi
        rm -f -- "$2"
        ;;
    clear)
        rm -f -- "$entries"/* 2>/dev/null
        : > "$index"
        ;;
    *)
        exit 1
        ;;
esac
