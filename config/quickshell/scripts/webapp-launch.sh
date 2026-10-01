#!/bin/bash

# selah-webapp-launch — open a URL as a standalone app window (no browser
# chrome, no tab strip), the way a native app would.
#
# Port of omarchy/bin/omarchy-launch-webapp, trimmed for this machine:
#   * omarchy launches through `uwsm-app` to attach the window to the uwsm
#     user session. uwsm is not installed here, so the browser is exec'd
#     directly.
#   * everything else (default-browser lookup, hard fall back to chromium
#     for anything that is not a Chromium-family browser) is kept as-is.
#
# Called from every generated .desktop file, by absolute path — this
# directory is NOT on $PATH, so an Exec of a bare script name would fail
# the moment the launcher tried to start it.

set -u

if [ $# -lt 1 ]; then
    echo "Usage: webapp-launch.sh <url> [extra browser flags...]" >&2
    exit 1
fi

url=$1
shift

# Read Exec= out of a desktop entry: the browser's real binary may be
# /usr/bin/chromium or chromium or a wrapper, and only the .desktop file
# knows which.
exec_of_desktop() {
    local dir
    for dir in \
        "$HOME/.local/share/applications" \
        "$HOME/.nix-profile/share/applications" \
        /usr/share/applications; do
        if [ -f "$dir/$1" ]; then
            sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$dir/$1" | head -1
            return 0
        fi
    done
    return 1
}

browser=$(xdg-settings get default-web-browser 2>/dev/null || true)

# Only Chromium-family browsers reliably honour --app=. Anything else
# (firefox, epiphany, ...) would just open a normal tabbed window, which
# silently defeats the point of a webapp launcher.
case $browser in
google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium*) ;;
*) browser="chromium.desktop" ;;
esac

bin=$(exec_of_desktop "$browser") || bin=""
if [ -z "$bin" ]; then
    bin=$(command -v chromium || command -v google-chrome || true)
fi
if [ -z "$bin" ]; then
    echo "webapp-launch.sh: no Chromium-family browser found" >&2
    exit 1
fi

# Ctrl+D video downloader: webapp windows carry the selah-video-dl
# extension, so pressing Ctrl+D on a playing video saves it into
# ~/Videos (see ~/.local/share/selah-video-dl/). --load-extension only
# applies to the process that STARTS the browser - if a plain chromium is
# already running, this launch silently attaches to it without the
# extension, so warn instead of leaving Ctrl+D mysteriously dead.
ext_dir="$HOME/.local/share/selah-video-dl/extension"
if [ -d "$ext_dir" ]; then
    if pgrep -x chromium >/dev/null 2>&1 || pgrep -f '/chromium[ ]' >/dev/null 2>&1; then
        if ! pgrep -af chromium | grep -q -- '--load-extension=[^ ]*selah-video-dl'; then
            notify-send -u normal -a Selah -i dialog-warning \
                "Ctrl+D downloads unavailable" \
                "Chromium is running without the download extension. Fully quit it, then reopen the webapp." \
                >/dev/null 2>&1 || true
        fi
    fi
    exec "$bin" --app="$url" --load-extension="$ext_dir" "$@"
fi

exec "$bin" --app="$url" "$@"
