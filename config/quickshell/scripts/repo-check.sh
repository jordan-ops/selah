#!/usr/bin/env bash
# Is this clone behind the remote it came from? One cheap `ls-remote` — no
# fetch, no local mutation, safe to run every ten minutes from the shell's
# timer. services/Updates.qml parses stdout; the contract is EXACTLY one
# line, one of:
#   uptodate  <local-sha>
#   available <remote-sha> <local-sha>
#   error     <short-reason>
# Errors print instead of hanging or failing: an offline machine or a
# missing gh credential must never pop a dialog or spam the log.
set -u

# repo root, derived from this script's real path (config/quickshell/scripts)
root=$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)

command -v git >/dev/null 2>&1 || { echo "error no-git"; exit 0; }
local=$(git -C "$root" rev-parse HEAD 2>/dev/null) || { echo "error not-a-repo"; exit 0; }
branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)

# GitHub answers anywhere between 1s and ~10s from some networks, and a
# single probe occasionally comes back empty — one flake must not flip the
# shell into "error" for ten minutes, so probe up to three times with a
# short breather between attempts (fast failure when genuinely offline:
# each attempt errors out immediately without a connection).
remote=""
for try in 1 2 3; do
    remote=$(timeout 15 git -C "$root" ls-remote origin "refs/heads/$branch" 2>/dev/null | cut -f1)
    [ -n "$remote" ] && break
    [ "$try" -lt 3 ] && sleep 2
done
[ -n "$remote" ] || { echo "error unreachable"; exit 0; }

if [ "$remote" = "$local" ]; then
    echo "uptodate $local"
else
    echo "available $remote $local"
fi
exit 0
