#!/bin/sh
# Copies the qbittorrent-nox engine into Sprout.app/Contents/Helpers and signs it.
# Override the source with QBT_ENGINE_BINARY. The default is a local dev build that
# links Homebrew libraries, so the resulting app only runs on a machine with them.
set -eu
ENGINE="${QBT_ENGINE_BINARY:-$SRCROOT/../../oss/qbt-engine-build/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox}"
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
if [ ! -x "$ENGINE" ]; then
  echo "error: engine not found at $ENGINE (set QBT_ENGINE_BINARY)"
  exit 1
fi
mkdir -p "$DEST"
cp -f "$ENGINE" "$DEST/qbittorrent-nox"
codesign --force --sign - "$DEST/qbittorrent-nox"
