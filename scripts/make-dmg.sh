#!/bin/bash
# Builds a universal Release Sprout.app, wraps it in build/dmg/Sprout-<version>.dmg, signs the
# DMG for Sparkle and adds it to appcast.xml. Run scripts/build-static-engine.sh first.
#
#   scripts/make-dmg.sh            ad hoc signed (not notarized)
#   SIGN_IDENTITY=... scripts/make-dmg.sh   Developer ID (hardened runtime; notarize separately)
#
# The Sparkle private key is read from the login keychain, account dev.unhingedpanda.Sprout.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:--}"
OUT=build/release-dmg
APP="$OUT/Build/Products/Release/Sprout.app"
REPO=unhingedpanda/sprout
SPARKLE_BIN=$(find build -path '*artifacts/sparkle/Sparkle/bin' -type d | head -1)
[ -n "$SPARKLE_BIN" ] || { echo "error: resolve packages first (xcodebuild -resolvePackageDependencies)" >&2; exit 1; }

lipo -archs build/engine/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox | grep -q x86_64 \
  || { echo "error: build/engine is not universal; run scripts/build-static-engine.sh" >&2; exit 1; }

xcodegen generate -q
runtime=NO; [ "$IDENTITY" != "-" ] && runtime=YES
rm -rf "$OUT"
# Stripped: debug symbols carry the build machine's paths.
xcodebuild -project Sprout.xcodeproj -scheme Sprout -configuration Release -derivedDataPath "$OUT" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$IDENTITY" ENABLE_HARDENED_RUNTIME=$runtime \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global build -quiet

codesign --verify --deep --strict "$APP"
if grep -rlaE "/Users/|$(id -un)" "$APP" >/dev/null; then
  echo "error: the app contains build-machine paths:" >&2; grep -rlaE "/Users/|$(id -un)" "$APP" >&2; exit 1
fi
for f in "$APP/Contents/MacOS/Sprout" "$APP/Contents/Helpers/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox"; do
  [ "$(lipo -archs "$f")" = "x86_64 arm64" ] || { echo "error: $f is $(lipo -archs "$f")" >&2; exit 1; }
done

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")
MIN_OS=$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")
DMG="build/dmg/Sprout-$VERSION.dmg"
mkdir -p build/dmg && rm -rf build/dmg/stage && mkdir build/dmg/stage
ditto "$APP" build/dmg/stage/Sprout.app && ln -s /Applications build/dmg/stage/Applications
hdiutil create -volname "Sprout $VERSION" -srcfolder build/dmg/stage -fs APFS -format ULFO -ov "$DMG" -quiet
rm -rf build/dmg/stage
[ "$IDENTITY" != "-" ] && codesign --force --sign "$IDENTITY" --timestamp "$DMG"
hdiutil verify "$DMG" -quiet

SIG=$("$SPARKLE_BIN/sign_update" --account dev.unhingedpanda.Sprout "$DMG")
python3 - "$VERSION" "$BUILD" "$MIN_OS" "$REPO" "$SIG" <<'PY'
import sys, os, email.utils
version, build, min_os, repo, sig = sys.argv[1:]
item = f"""    <item>
      <title>Sprout {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/{repo}/releases/tag/v{version}</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/{repo}/releases/download/v{version}/Sprout-{version}.dmg" type="application/octet-stream" {sig}/>
    </item>
"""
path = "appcast.xml"
if os.path.exists(path):
    text = open(path).read()
    if f"<sparkle:version>{build}</sparkle:version>" in text:
        sys.exit(f"error: appcast already has build {build}; raise CURRENT_PROJECT_VERSION")
    text = text.replace("    <item>", item + "    <item>", 1) if "<item>" in text else text.replace("  </channel>", item + "  </channel>")
else:
    text = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sprout</title>
    <link>https://github.com/{repo}</link>
{item}  </channel>
</rss>
"""
open(path, "w").write(text)
PY
echo "==> $DMG ($(du -h "$DMG" | cut -f1)), appcast.xml updated"
shasum -a 256 "$DMG"
