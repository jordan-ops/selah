#!/usr/bin/env bash
# The "Update" button on the update popup: fast-forward the clone, then
# re-run the config-only install (links, state seeds, theme apply — no
# sudo, no packages, no nvim sync). quickshell starts this DETACHED
# (execDetached), because the pull itself changes the config dir and
# triggers a shell reload — a still-attached process would be killed
# halfway through.
#
# Progress is reported through a one-word state file that Updates.qml
# polls:  running -> done | failed.  Full output lands in the log so a
# failure can be read after the fact.
set -u

root=$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)
dir="$HOME/.local/state/quickshell"
state="$dir/repo-update.state"
log="$dir/repo-update.log"
mkdir -p "$dir"

printf 'running' > "$state"
{
    echo "=== repo update $(date '+%Y-%m-%d %H:%M:%S') ==="
    if ! git -C "$root" pull --ff-only; then
        echo "pull failed — local changes or diverged history (see git status)"
        printf 'failed' > "$state"
        exit 1
    fi
    if ! bash "$root/install.sh" --skip-nvim; then
        echo "install.sh failed"
        printf 'failed' > "$state"
        exit 1
    fi
    echo "ok"
    printf 'done' > "$state"
} >>"$log" 2>&1
exit 0
