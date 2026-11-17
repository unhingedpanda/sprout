# Sprout

A native macOS front end for the qBittorrent engine. Sprout bundles qBittorrent's headless
engine (`qbittorrent-nox`), starts it when the app opens, and drives it over the engine's
local Web API. "Sprout" is a working name.

Sprout is not an official qBittorrent product.

## Requirements

- macOS 26 or later
- Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A `qbittorrent-nox` build (see below)

## Build the engine (development)

The development build links Homebrew libraries, so the resulting app only runs on a Mac
that has them installed. A self-contained engine is still to do.

```sh
brew install cmake ninja libtorrent-rasterbar qtbase qttools
git clone https://github.com/qbittorrent/qBittorrent.git --branch release-5.3.0 qbt-engine-src
cmake -S qbt-engine-src -B qbt-engine-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGUI=OFF -DWEBUI=ON -DSTACKTRACE=OFF -DCMAKE_PREFIX_PATH=/opt/homebrew
ninja -C qbt-engine-build
```

## Build the app

```sh
xcodegen generate
QBT_ENGINE_BINARY=/path/to/qbt-engine-build/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox \
  xcodebuild -project Sprout.xcodeproj -scheme Sprout build
```

`scripts/embed-engine.sh` copies the engine into `Sprout.app/Contents/Helpers`. Without
`QBT_ENGINE_BINARY` it looks for `../../oss/qbt-engine-build` next to this folder.

## How the engine is run

- Profile: `~/Library/Application Support/Sprout/Engine` (log: `engine.log` there).
- The Web API listens on `127.0.0.1` only, on a free port chosen at each launch.
- Sprout writes a random API key into the engine's config and sends it as a bearer token.
  Localhost authentication stays on, so other programs can't drive the engine without it.
- Quitting Sprout asks the engine to save resume data and exit. Closing the window does not
  quit: torrents keep running, like other Mac clients.

## Not done yet

- Self-contained, universal engine build; hardened runtime, signing and notarization.
- App icon and final name.
- Settings window (speed limits, ports, default folder).
- Completion notifications; restarting an engine left running after a crash.

## Licence

GPL-3.0-or-later. Sprout bundles a qBittorrent engine binary, which is distributed under
GPLv3+. See `LICENSE`.
