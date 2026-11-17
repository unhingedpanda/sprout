#!/bin/sh
# Copies the self-contained engine bundle into Sprout.app/Contents/Helpers.
# Make the bundle first with scripts/bundle-engine.sh, or point QBT_ENGINE_APP at one.
set -eu
ENGINE="${QBT_ENGINE_APP:-$SRCROOT/build/engine/qbittorrent-nox.app}"
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
if [ ! -d "$ENGINE" ]; then
  echo "error: engine bundle not found at $ENGINE (run scripts/bundle-engine.sh or set QBT_ENGINE_APP)"
  exit 1
fi
rm -rf "$DEST" && mkdir -p "$DEST"
ditto "$ENGINE" "$DEST/qbittorrent-nox.app"
