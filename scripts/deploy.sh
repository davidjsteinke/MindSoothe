#!/usr/bin/env bash
# Sync the addon to WoW's AddOns directory on Windows.
#
# Usage:
#   ./scripts/deploy.sh          # ship build  -> MindSoothe/  (verbatim, no stamping)
#   ./scripts/deploy.sh ship     # same as the default
#   ./scripts/deploy.sh dev      # dev twin     -> MindDev/      (identity stamped)
#
# The committed addon/ tree IS the ship identity ("Mind Soothe"), so the ship
# build is a straight rsync with no transformation — what ships is exactly what
# is in git. The dev build is a private twin produced by staging a throwaway copy
# and applying three identity substitutions, so ship + dev coexist in one client
# with ZERO collision: distinct folder, TOC Title, slash, SavedVariables, AceAddon
# /AceConfig registration name, and global frame name all differ.
#
# The dev build is LOCAL-ONLY. It is staged under .build/ (gitignored), never
# committed, and excluded from the package (.pkgmeta). The public product is
# "Mind Soothe" only.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON_SRC="$PROJECT_ROOT/addon"
ADDONS_DIR="/mnt/g/Blizzard/World of Warcraft/_retail_/Interface/AddOns"

TARGET="${1:-ship}"

if [[ ! -d "$ADDON_SRC" ]]; then
    echo "Error: $ADDON_SRC does not exist yet. Run from project root after addon/ exists."
    exit 1
fi

deploy_ship() {
    local dst="$ADDONS_DIR/MindSoothe"
    mkdir -p "$dst"
    rsync -av --delete "$ADDON_SRC/" "$dst/"
    echo "Deployed ship build (Mind Soothe) to $dst"
}

deploy_dev() {
    local stage="$PROJECT_ROOT/.build/MindDev"
    local dst="$ADDONS_DIR/MindDev"

    rm -rf "$stage"
    mkdir -p "$stage"
    # Stage a full copy (Libs included, copied as-is — substitution skips it).
    rsync -a "$ADDON_SRC/" "$stage/"

    # Three identity substitutions, applied to text files only and NOT to Libs/
    # (third-party). Order is safe: "MindSoothe" (no space) and "Mind Soothe"
    # (space) are disjoint tokens, and "/mind" requires a leading slash so it
    # never touches words like "reminders".
    #   MindSoothe  -> MindDev    (folder/SV/registration/frame/APP identifiers)
    #   Mind Soothe -> Mind Dev   (TOC Title, panel title, chat prefix)
    #   /mind       -> /mdev      (slash token + all help/description copy)
    while IFS= read -r -d '' f; do
        sed -i \
            -e 's/MindSoothe/MindDev/g' \
            -e 's/Mind Soothe/Mind Dev/g' \
            -e 's#/mind#/mdev#g' \
            "$f"
    done < <(find "$stage" -path "$stage/Libs" -prune -o \
                  -type f \( -name '*.lua' -o -name '*.toc' -o -name '*.md' \) -print0)

    # The .toc filename must match the addon folder name.
    mv "$stage/MindSoothe.toc" "$stage/MindDev.toc"
    # The stamp also rewrote the TOC's reference to the main Lua file
    # (MindSoothe.lua -> MindDev.lua), so the file on disk must match that
    # reference or WoW silently skips it and the addon never registers its slash.
    mv "$stage/MindSoothe.lua" "$stage/MindDev.lua"

    mkdir -p "$dst"
    rsync -av --delete "$stage/" "$dst/"
    echo "Deployed dev build (Mind Dev) to $dst"
}

case "$TARGET" in
    ship) deploy_ship ;;
    dev)  deploy_dev ;;
    *)    echo "Unknown target '$TARGET' (use: ship | dev)"; exit 1 ;;
esac
