#!/bin/bash
# Turns a qbittorrent-nox.app build into a self-contained bundle: Qt, libtorrent and OpenSSL
# are copied in with macdeployqt, GUI-only parts are removed, and every binary is signed.
#
#   scripts/bundle-engine.sh [path/to/qbittorrent-nox.app] [output dir]
#
# SIGN_IDENTITY picks the signing identity (default "-", ad hoc). With a Developer ID,
# binaries get the hardened runtime and a secure timestamp, ready for notarization.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-../../oss/qbt-engine-build/qbittorrent-nox.app}"
OUT="${2:-build/engine}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="$OUT/qbittorrent-nox.app"
C="$APP/Contents"

rm -rf "$APP" && mkdir -p "$OUT" && cp -R "$SRC" "$APP"
# QtSvg is absent and only the SVG icon plugin wants it: that plugin is removed below.
macdeployqt "$APP" 2>&1 | grep -v 'QtSvg' || true

# The engine is headless: no windows, styles, icons or images. glib network info is Linux's.
rm -rf "$C/PlugIns/"{platforms,styles,iconengines,imageformats} "$C/PlugIns/networkinformation/libqglib.dylib"

# Resolve @rpath inside the bundle only, never against Homebrew.
EXE="$C/MacOS/qbittorrent-nox"
for r in $(otool -l "$EXE" | awk '/LC_RPATH/{getline; getline; print $2}'); do
  install_name_tool -delete_rpath "$r" "$EXE"
done
install_name_tool -add_rpath @executable_path/../Frameworks "$EXE"

# Keep only the libraries the engine and the kept plugins load, directly or indirectly.
keep=$(mktemp); queue=("$EXE" $(find "$C/PlugIns" -name '*.dylib'))
while ((${#queue[@]})); do
  f=${queue[0]}; queue=("${queue[@]:1}")
  for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | sed -nE 's#^@(executable_path/\.\./Frameworks|rpath)/##p'); do
    top=${dep%%/*}
    grep -qxF "$top" "$keep" && continue
    echo "$top" >> "$keep"
    queue+=("$C/Frameworks/$dep")
  done
done
for f in "$C/Frameworks/"*; do
  grep -qxF "$(basename "$f")" "$keep" || rm -rf "$f"
done
rm "$keep"

# Fail if anything still points outside the bundle.
if find "$C" -type f \( -perm -u+x -o -name '*.dylib' \) -exec otool -L {} \; 2>/dev/null | grep -E '^\s+/(opt|usr/local)/'; then
  echo "error: the bundle still links libraries outside itself" >&2; exit 1
fi

# Sign inside out: libraries and plugins, then frameworks, then the app.
flags=(--force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && flags+=(--options runtime --timestamp)
find "$C/Frameworks" "$C/PlugIns" -name '*.dylib' -exec codesign "${flags[@]}" {} +
for fw in "$C/Frameworks/"*.framework; do codesign "${flags[@]}" "$fw"; done
codesign "${flags[@]}" "$APP"
codesign --verify --strict --deep "$APP"
du -sh "$APP"
