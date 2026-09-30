#!/usr/bin/env bash
# seed-wallpapers.sh — make aether's scan dir see the wallpapers you already have.
#
# aether only ever lists ~/Wallpapers (internal/wallpaper/local.go:
# ScanDefaultDirs -> platform.WallpaperDir), so wallpapers that live inside
# ~/.config/themes/<name>/backgrounds are invisible to it. This drops one
# symlink per wallpaper into ~/Wallpapers, prefixed with its theme so names
# stay unique across all themes:
#
#     nord--default.jpg  ->  ~/.config/themes/nord/backgrounds/default.jpg
#
# Symlinks, not copies: ~92 files / tens of MB, and deleting ~/Wallpapers
# reverts everything. aether resolves through them fine — it stats with
# os.Stat and stages a real copy only when a theme is actually generated.
#
# Idempotent: re-running refreshes the links and prunes any whose source
# has since been deleted. Nothing here is ever written outside ~/Wallpapers.

set -euo pipefail

HOME_DIR="${HOME:?HOME is not set}"
THEMES="$HOME_DIR/.config/themes"
DEST="$HOME_DIR/Wallpapers"

mkdir -p "$DEST"

is_image() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *.jpg|*.jpeg|*.png|*.webp|*.bmp|*.tif|*.tiff) return 0 ;;
        *) return 1 ;;
    esac
}

# Prune links we created whose source has disappeared (theme deleted,
# wallpaper removed) so the list never shows dead entries.
if [ -d "$DEST" ]; then
    find "$DEST" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true
fi

created=0
skipped=0

[ -d "$THEMES" ] || { echo "seed-wallpapers: no $THEMES" >&2; exit 1; }

for bg in "$THEMES"/*/backgrounds; do
    [ -d "$bg" ] || continue
    theme="$(basename "$(dirname "$bg")")"

    # Find images up to two levels deep; deeper is not worth flattening.
    while IFS= read -r -d '' file; do
        is_image "$file" || continue

        base="$(basename "$file")"
        # Flatten subfolders so nothing collides: theme--sub--name.jpg
        rel="${file#"$bg"/}"
        if [ "$rel" != "$base" ]; then
            sub="$(dirname "$rel")"
            sub="$(printf '%s' "$sub" | tr '/' '-')"
            name="${theme}--${sub}--${base}"
        else
            name="${theme}--${base}"
        fi

        # Spaces/# in the target are fine (the link name is ours, and the
        # picker URL-encodes the resolved path).
        if [ -L "$DEST/$name" ] && [ "$(readlink -f "$DEST/$name")" = "$(readlink -f "$file")" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        ln -sfn "$file" "$DEST/$name"
        created=$((created + 1))
    done < <(find "$bg" -maxdepth 2 -type f -print0 2>/dev/null)
done

total="$(find "$DEST" -maxdepth 1 -type l 2>/dev/null | wc -l)"
echo "seed-wallpapers: $created created, $skipped already current, $total linked total"
echo "  -> $DEST"
