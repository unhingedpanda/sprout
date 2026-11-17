#!/bin/bash
# Builds a Developer ID signed Sprout.app with the self-contained engine, then notarizes it,
# staples the ticket and writes build/release/Sprout.zip.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=profile scripts/release.sh
#
# NOTARY_PROFILE is a `xcrun notarytool store-credentials` profile. Without it the script
# stops after signing and checking, so the build can be inspected before submission.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to a Developer ID Application identity}"
OUT=build/release
APP="$OUT/Build/Products/Release/Sprout.app"

echo "==> engine"
SIGN_IDENTITY="$IDENTITY" scripts/bundle-engine.sh

echo "==> app"
xcodegen generate -q
# ponytail: arm64 only because the engine bundle is; go universal with a universal engine.
xcodebuild -project Sprout.xcodeproj -scheme Sprout -configuration Release -derivedDataPath "$OUT" \
  ARCHS=arm64 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp build -quiet

# The notary service rejects the whole upload for any one of these, minutes later, so check first.
echo "==> checking signatures"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q get-task-allow; then
  echo "error: get-task-allow is set" >&2; exit 1
fi
team=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
find "$APP" -type f | while read -r f; do
  file -b "$f" | grep -q Mach-O || continue
  info=$(codesign -dv --verbose=4 "$f" 2>&1)
  for want in "TeamIdentifier=$team" "flags=.*runtime" "^Timestamp="; do
    grep -Eq "$want" <<<"$info" || { echo "error: $f lacks $want" >&2; exit 1; }
  done
done

if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "==> signed and checked: $APP (set NOTARY_PROFILE to notarize)"; exit 0
fi

echo "==> notarizing"
ditto -c -k --keepParent "$APP" "$OUT/submit.zip"
xcrun notarytool submit "$OUT/submit.zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
xcrun stapler staple "$APP"
spctl --assess --type exec --verbose=4 "$APP" 2>&1 | tee /dev/stderr | grep -q "Notarized Developer ID"
ditto -c -k --keepParent "$APP" "$OUT/Sprout.zip"
rm "$OUT/submit.zip"
echo "==> $OUT/Sprout.zip notarized and stapled"
