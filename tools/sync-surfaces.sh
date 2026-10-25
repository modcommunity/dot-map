#!/usr/bin/env bash
#
# Copy the surface textures a game uses into the game (or check that they are all there).
#
#   tools/sync-surfaces.sh ../game-zombie-zone assets/surfaces              # the kinds in <dest>/kinds.txt
#   tools/sync-surfaces.sh ../game-zombie-zone assets/surfaces brick asphalt # these kinds, and write kinds.txt
#   tools/sync-surfaces.sh ../game-zombie-zone assets/surfaces --check      # copy nothing; exit 1 if anything is missing or differs
#
# Why a game vendors the textures instead of reading the addon's: the client shell bundles
# dot-map, and 12 MB of textures every game may never draw must not ride in it. A game ships
# exactly the kinds it names, inside its own signed pack, and hands DotMapSurfaces that root
# (docs/surfaces.md). The list lives in <dest>/kinds.txt, one kind per line, so the copy says
# what it is for and a later sync does not guess.
#
# What is copied per kind: albedo.jpg, normal.jpg, roughness.jpg, plus the .import file of each
# ONLY when the game has none yet (Godot rewrites an import file when it imports, so a second
# copy over it would be a diff for nothing). The licence text and CREDITS.md go with them, because
# a CC0 texture is credited anyway (the family's art rule).
set -euo pipefail

GAME="${1:?usage: tools/sync-surfaces.sh <game-dir> <dest-dir-in-game> [--check] [kind...]}"
DEST="${2:?usage: tools/sync-surfaces.sh <game-dir> <dest-dir-in-game> [--check] [kind...]}"
shift 2
CHECK=0
KINDS=()
for a in "$@"; do
    if [ "$a" = "--check" ]; then CHECK=1; else KINDS+=("$a"); fi
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/addons/dot_map/surfaces"
GAME="$(cd "$GAME" && pwd)"
OUT="$GAME/$DEST"
LIST="$OUT/kinds.txt"
FILES=(albedo.jpg normal.jpg roughness.jpg)
bad=0

if [ "${#KINDS[@]}" -eq 0 ]; then
    [ -f "$LIST" ] || { echo "no kinds named and $LIST does not exist" >&2; exit 2; }
    mapfile -t KINDS < <(grep -v '^[[:space:]]*\(#\|$\)' "$LIST")
fi

for k in "${KINDS[@]}"; do
    [ -d "$SRC/$k" ] || { echo "unknown kind '$k' (no $SRC/$k)" >&2; exit 2; }
done

if [ "$CHECK" -eq 0 ]; then
    mkdir -p "$OUT"
    printf '# Surface kinds this game vendors (dot-map tools/sync-surfaces.sh); one per line.\n' > "$LIST"
    printf '%s\n' "${KINDS[@]}" | sort -u >> "$LIST"
fi

for k in "${KINDS[@]}"; do
    for f in "${FILES[@]}"; do
        from="$SRC/$k/$f"
        to="$OUT/$k/$f"
        if [ "$CHECK" -eq 1 ]; then
            if [ ! -f "$to" ]; then echo "missing: $DEST/$k/$f"; bad=1
            elif ! cmp -s "$from" "$to"; then echo "differs: $DEST/$k/$f"; bad=1; fi
            [ -f "$to.import" ] || { echo "no import file: $DEST/$k/$f.import (open the project once)"; bad=1; }
            ! grep -q '^mipmaps/generate=false' "$to.import" 2>/dev/null || { echo "no mipmaps: $DEST/$k/$f.import (run the sync; surfaces shimmer at a distance without them)"; bad=1; }
        else
            mkdir -p "$OUT/$k"
            cmp -s "$from" "$to" 2>/dev/null || cp "$from" "$to"
            if [ ! -f "$to.import" ]; then
                # Source path rewritten and the uid and dest lines dropped: a copied uid would be the
                # addon's own, and a game that links dot-map then has two resources under one uid.
                # Godot writes a fresh uid and dest hash on its first import.
                sed -e "s#res://addons/dot_map/surfaces/#res://$DEST/#g" -e '/^uid=/d' -e '/^path=/d' -e '/^dest_files=/d' "$from.import" > "$to.import"
            fi
            # Mipmaps are not optional for a surface: a copy imported without them (as a game's own import settings may) is set right.
            sed -i 's#^mipmaps/generate=false#mipmaps/generate=true#' "$to.import"
        fi
    done
done

for f in CREDITS.md LICENSE.txt; do
    if [ "$CHECK" -eq 1 ]; then
        cmp -s "$SRC/$f" "$OUT/$f" || { echo "missing or differs: $DEST/$f"; bad=1; }
    else
        cmp -s "$SRC/$f" "$OUT/$f" 2>/dev/null || cp "$SRC/$f" "$OUT/$f"
    fi
done

if [ "$CHECK" -eq 1 ]; then
    [ "$bad" -eq 0 ] && echo "surfaces: ${#KINDS[@]} kinds in sync" || exit 1
else
    echo "surfaces: ${#KINDS[@]} kinds copied to $DEST"
fi
