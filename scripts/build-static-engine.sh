#!/bin/bash
# Builds a universal (Apple silicon + Intel) qbittorrent-nox with OpenSSL, Qt and libtorrent
# linked in statically, for macOS 26 and later. Homebrew's libraries target the build Mac's
# macOS and Apple silicon only, so they can't ship. Output: build/engine/qbittorrent-nox.app.
#
#   scripts/build-static-engine.sh [work dir]
#
# Needs: Xcode, cmake, ninja, and Homebrew's qtbase + qttools 6.12.0 (host tools for the Intel
# cross-build) and boost (headers only). Sources are downloaded from their official releases.
# SIGN_IDENTITY picks the signing identity (default "-", ad hoc).
#
# Licences: Qt is LGPL v3. Linking it statically is allowed because the whole engine is GPL v3
# and its full source, this script included, is public. Rebuild with a modified Qt by pointing
# QT_SRC at it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
WORK="${1:-$ROOT/../../oss/static-engine}"; mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
QBT_SRC=$(cd "${QBT_SRC:-$ROOT/../../oss/qbt-engine-src}" && pwd)
IDENTITY="${SIGN_IDENTITY:--}"
TARGET=26.0
QT_V=6.12.0 OPENSSL_V=4.1.0 LT_V=2.1.2
HB=/opt/homebrew
JOBS=$(sysctl -n hw.ncpu)
export MACOSX_DEPLOYMENT_TARGET=$TARGET

mkdir -p "$WORK/src" && cd "$WORK/src"
fetch() { [ -f "$(basename "$1")" ] || curl -fL --retry 3 -O "$1"; }
fetch https://download.qt.io/official_releases/qt/${QT_V%.*}/$QT_V/submodules/qtbase-everywhere-src-$QT_V.tar.xz
fetch https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_V/openssl-$OPENSSL_V.tar.gz
fetch https://github.com/arvidn/libtorrent/releases/download/v$LT_V/libtorrent-rasterbar-$LT_V.tar.gz
[ -d qtbase-everywhere-src-$QT_V ] || tar xf qtbase-everywhere-src-$QT_V.tar.xz
[ -d libtorrent-rasterbar-$LT_V ] || tar xf libtorrent-rasterbar-$LT_V.tar.gz
QT_SRC="${QT_SRC:-$WORK/src/qtbase-everywhere-src-$QT_V}"

# The binary ships, so it must not carry this Mac's paths: source paths are remapped, and
# OpenSSL and Qt are configured for a neutral prefix, then installed under the work folder.
NEUTRAL=/opt/sprout-engine
MAP="-ffile-prefix-map=$WORK=/engine -ffile-prefix-map=$QBT_SRC=/qbittorrent"
for ARCH in arm64 x86_64; do
  P="$WORK/stage-$ARCH$NEUTRAL"; B="$WORK/build-$ARCH"; mkdir -p "$P" "$B"
  common=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=$ARCH
          -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET -DBUILD_SHARED_LIBS=OFF
          -DCMAKE_C_FLAGS="$MAP" -DCMAKE_CXX_FLAGS="$MAP")
  # The Intel build runs no Intel code: Qt's code generators come from the Homebrew host Qt.
  host=(); [ "$ARCH" = x86_64 ] && host=(-DQT_HOST_PATH=$HB)

  if [ ! -f "$P/lib/libssl.a" ]; then
    rm -rf "$B/openssl" && mkdir -p "$B/openssl" && tar xf "$WORK/src/openssl-$OPENSSL_V.tar.gz" -C "$B/openssl" --strip-components 1
    (cd "$B/openssl" && ./Configure darwin64-$ARCH-cc no-shared no-tests no-docs --prefix=$NEUTRAL --libdir=lib \
       --openssldir=/private/etc/ssl -mmacosx-version-min=$TARGET $MAP \
       && make crypto/buildinf.h >/dev/null \
       && rm -f crypto/buildinf.h && perl util/mkbuildinf.pl "clang -arch $ARCH -O3 -mmacosx-version-min=$TARGET" "darwin64-$ARCH-cc" > crypto/buildinf.h \
       && make -j$JOBS >/dev/null && make install_sw DESTDIR="$WORK/stage-$ARCH" >/dev/null)
  fi

  if [ ! -f "$P/qt/lib/libQt6Core.a" ]; then
    cmake -S "$QT_SRC" -B "$B/qt" "${common[@]}" ${host[@]+"${host[@]}"} -DCMAKE_INSTALL_PREFIX=$NEUTRAL/qt \
      -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DQT_BUILD_BENCHMARKS=OFF \
      -DFEATURE_gui=OFF -DFEATURE_widgets=OFF -DFEATURE_dbus=OFF -DFEATURE_testlib=OFF \
      -DFEATURE_concurrent=OFF -DFEATURE_printsupport=OFF -DFEATURE_opengl=OFF \
      -DFEATURE_icu=OFF -DFEATURE_glib=OFF -DFEATURE_zstd=OFF -DFEATURE_brotli=OFF \
      -DFEATURE_system_pcre2=OFF -DFEATURE_system_doubleconversion=OFF -DFEATURE_system_libb2=OFF \
      -DFEATURE_system_zlib=ON -DFEATURE_sql_sqlite=ON -DFEATURE_system_sqlite=OFF \
      -DFEATURE_sql_odbc=OFF -DFEATURE_sql_psql=OFF -DFEATURE_sql_mysql=OFF -DFEATURE_sql_ibase=OFF \
      -DFEATURE_openssl=ON -DFEATURE_openssl_linked=ON -DFEATURE_securetransport=OFF \
      -DOPENSSL_ROOT_DIR="$P" -DOPENSSL_USE_STATIC_LIBS=ON
    cmake --build "$B/qt" && cmake --install "$B/qt" --prefix "$P/qt" >/dev/null
  fi

  if [ ! -f "$P/lt/lib/libtorrent-rasterbar.a" ]; then
    cmake -S "$WORK/src/libtorrent-rasterbar-$LT_V" -B "$B/lt" "${common[@]}" -DCMAKE_INSTALL_PREFIX="$P/lt" \
      -DCMAKE_CXX_STANDARD=20 -Ddeprecated-functions=OFF -DBoost_DIR=$HB/lib/cmake/Boost-$(brew list --versions boost | awk '{print $2}' | cut -d_ -f1) \
      -DOPENSSL_ROOT_DIR="$P" -DOPENSSL_USE_STATIC_LIBS=ON
    cmake --build "$B/lt" && cmake --install "$B/lt" >/dev/null
  fi

  # OpenSSL is named file by file: the Homebrew paths for Boost and Linguist would otherwise
  # supply Homebrew's OpenSSL, built for the build Mac only.
  rm -rf "$B/qbt"
  cmake -S "$QBT_SRC" -B "$B/qbt" "${common[@]}" ${host[@]+"${host[@]}"} -DGUI=OFF -DWEBUI=ON -DSTACKTRACE=OFF \
    -DCMAKE_PREFIX_PATH="$P/qt;$P/lt" -DQt6LinguistTools_DIR=$HB/lib/cmake/Qt6LinguistTools \
    -DBoost_DIR=$HB/lib/cmake/Boost-$(brew list --versions boost | awk '{print $2}' | cut -d_ -f1) \
    -DOPENSSL_ROOT_DIR="$P" -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOpenSSL_DIR="$P/lib/cmake/OpenSSL" -DOPENSSL_INCLUDE_DIR="$P/include" -DOPENSSL_SSL_LIBRARY="$P/lib/libssl.a" -DOPENSSL_CRYPTO_LIBRARY="$P/lib/libcrypto.a"
  cmake --build "$B/qbt"
done

# One bundle, one universal executable. Nothing to bundle beside it: every library is inside.
OUT="$ROOT/build/engine/qbittorrent-nox.app"
rm -rf "$OUT" && mkdir -p "$(dirname "$OUT")" && cp -R "$WORK/build-arm64/qbt/qbittorrent-nox.app" "$OUT"
EXE="$OUT/Contents/MacOS/qbittorrent-nox"
lipo -create "$WORK/build-arm64/qbt/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox" \
             "$WORK/build-x86_64/qbt/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox" -output "$EXE"

for ARCH in arm64 x86_64; do
  if grep -q "$WORK\|$HOME" "$EXE"; then echo "error: the engine contains build-machine paths" >&2; exit 1; fi
  if otool -arch $ARCH -L "$EXE" | tail -n +2 | awk '{print $1}' | grep -vE '^/(usr/lib|System/Library)/'; then
    echo "error: the $ARCH engine links a library outside macOS" >&2; exit 1
  fi
  minos=$(vtool -arch $ARCH -show-build "$EXE" | awk '/minos/{print $2}')
  [ "$minos" = "$TARGET" ] || { echo "error: $ARCH engine targets macOS $minos, not $TARGET" >&2; exit 1; }
done

flags=(--force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && flags+=(--options runtime --timestamp)
codesign "${flags[@]}" "$OUT"
codesign --verify --strict --deep "$OUT"
lipo -archs "$EXE" && du -sh "$OUT"
