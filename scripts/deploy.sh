#!/usr/bin/env bash
# Sync the addon folder to WoW's AddOns directory on Windows.
# Usage: ./scripts/deploy.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON_SRC="$PROJECT_ROOT/addon"
ADDON_DST="/mnt/g/Blizzard/World of Warcraft/_retail_/Interface/AddOns/ToxFilter"

if [[ ! -d "$ADDON_SRC" ]]; then
    echo "Error: $ADDON_SRC does not exist yet. Run from project root after addon/ exists."
    exit 1
fi

mkdir -p "$ADDON_DST"
rsync -av --delete "$ADDON_SRC/" "$ADDON_DST/"
echo "Deployed to $ADDON_DST"
