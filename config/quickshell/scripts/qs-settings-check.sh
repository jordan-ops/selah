#!/usr/bin/env bash
# qs-settings-check — CI-style health check for the quickshell settings
# catalog. Boots a THROWAWAY quickshell instance against a symlink-farm
# of the real config (a probe shell.qml swapped in) and asserts the
# SettingsCatalog singletons load with the invariants the settings window
# and the launcher's ">" search depend on. Invariants, not exact numbers
# — the catalog grows. PASS = exit 0, FAIL = exit 1 (prints the captured
# instance output + a hint). Override the config dir with QSCONFIG_DIR
# (used to exercise the failure path against a deliberately broken copy).
set -u

CONF_DIR="${QSCONFIG_DIR:-/home/jordan-sama/.config/quickshell}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# symlink-farm the config — every entry except the real shell.qml, which
# the probe below replaces
for f in "$CONF_DIR"/*; do
    base=$(basename "$f")
    [ "$base" = "shell.qml" ] && continue
    ln -s "$f" "$tmp/$base"
done

# probe: imports "services" as the real shell does, touches the catalog
# singletons, prints ONE machine-readable marker line, quits. Instantiates
# no windows, engages no lock, writes nothing.
cat > "$tmp/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import "services" as Services

ShellRoot {
    Item {
        Component.onCompleted: {
            try {
                const cat = Services.SettingsCatalog
                console.log("QSCHECK pages=" + cat.pages.length
                    + " entries=" + cat.entries.length
                    + " searchable=" + cat.searchable.length
                    + " hyprParse=" + typeof cat.hyprParse)
            } catch (e) {
                console.log("QSCHECK error: " + e)
            }
            // quickshell 0.3.1 has no Quickshell.quit()/exit() — the
            // `timeout 15` around the qs call below tears the probe down;
            // calling quit() here just logged a TypeError each run.
        }
    }
}
EOF

out=$(timeout 10 qs -p "$tmp" 2>&1)
line=$(printf '%s\n' "$out" | grep -m1 'QSCHECK pages=' || true)

fail() {
    echo "FAIL: $1"
    echo "--- captured qs output ---"
    printf '%s\n' "$out"
    echo "--------------------------"
    echo "SettingsCatalog failed to load — check /run/user/1000/quickshell/by-id/<id>/log.log;"
    echo "known cause: pragma Singleton must be the FIRST line of the file"
    exit 1
}

[ -n "$line" ] || fail "no QSCHECK marker (catalog did not load, or the probe crashed before it)"

pages=$(sed -n 's/.*QSCHECK pages=\([0-9]*\).*/\1/p' <<<"$line")
entries=$(sed -n 's/.* entries=\([0-9]*\).*/\1/p' <<<"$line")
searchable=$(sed -n 's/.* searchable=\([0-9]*\).*/\1/p' <<<"$line")
hyprParse=$(sed -n 's/.* hyprParse=\([A-Za-z]*\).*/\1/p' <<<"$line")

[ -n "$pages" ] && [ -n "$entries" ] && [ -n "$searchable" ] && [ -n "$hyprParse" ] \
    || fail "malformed marker: $line"

# invariants (the catalog grows — never exact numbers)
[ "$pages" -ge 10 ]           || fail "pages=$pages (want >= 10)"
[ "$entries" -ge 50 ]        || fail "entries=$entries (want >= 50)"
[ "$searchable" -ge 40 ]     || fail "searchable=$searchable (want >= 40)"
[ "$searchable" -le "$entries" ] || fail "searchable=$searchable > entries=$entries"
[ "$hyprParse" = "function" ] || fail "typeof SettingsCatalog.hyprParse = $hyprParse (want function)"

echo "PASS: pages=$pages entries=$entries searchable=$searchable hyprParse=$hyprParse"
exit 0
