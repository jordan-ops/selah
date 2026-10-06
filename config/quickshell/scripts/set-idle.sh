#!/bin/sh
# Idle timeout store for the settings app — ~/.config/omarchy/shell.json
# ("idle": { "screensaver": 150, "lock": 300 }).
#
# There is no jq on this box, so python3 does the JSON edit: temp file in
# the same directory, then rename (atomic), indent 2 so the diff against
# the untouched keys stays one line. The screensaver and lock services
# watch the same file with FileView, so a set lands live — no reload.
set -u

usage() { echo "Usage: set-idle.sh get|set <screensaver|lock> [seconds]" >&2; exit 2; }
[ $# -ge 2 ] || usage
MODE=$1
KEY=$2
F="$HOME/.config/omarchy/shell.json"

case "$KEY" in
  screensaver|lock) ;;
  *) echo "refusing key: $KEY" >&2; exit 1 ;;
esac

case "$MODE" in
  get)
    exec python3 -c 'import json, sys
try:
    print(json.load(open(sys.argv[1])).get("idle", {}).get(sys.argv[2], ""))
except Exception:
    print("")' "$F" "$KEY"
    ;;
  set)
    [ $# -eq 3 ] || usage
    # values land in JSON — digits only, nothing that could break out
    case "$3" in
      *[!0-9]*|'') echo "refusing seconds: $3" >&2; exit 1 ;;
    esac
    exec python3 -c 'import json, os, sys
f, key, secs = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = json.load(open(f))
d.setdefault("idle", {})[key] = secs
tmp = f + ".tmp"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
os.replace(tmp, f)' "$F" "$KEY" "$3"
    ;;
  *) usage ;;
esac
