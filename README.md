<img src="docs/icon.png" width="128" alt="Sprout's icon: a seedling drawn in white dots on a black LED panel, with one orange dot at the tip">

# Sprout

A native macOS front end for the qBittorrent engine. Sprout bundles qBittorrent's headless
engine (`qbittorrent-nox`), starts it when the app opens, and drives it over the engine's
local Web API.

Sprout is not an official qBittorrent product.

## What it does

- Adds magnet links, `.torrent` files and URLs from the browser, Finder, drag and drop or ⌘O.
  Torrents can be added stopped, or held until their file list arrives so you can pick files first.
- Start, stop, force start, remove, verify local data, ask trackers for more peers, download in
  order, move files, rename, and reorder the queue, from the Torrent menu or a right-click.
- Categories and tags, with sidebar filters for both.
- An inspector with the piece map, files and their priorities, peers and trackers.
- Settings for speed limits and alternative limits (⌥⌘L), seeding limits, queue limits, the
  default folder and the listening port.
- A notification when a download finishes, a Dock badge, and an optional hold on idle sleep
  while anything downloads.
- Adding a torrent you already have merges the new source's trackers and web seeds into it
  (private torrents excepted) and says so, instead of failing.
- Edit trackers and web seeds, add or ban peers, rename files and folders, set per-torrent
  speed and seeding limits, copy magnet links, export .torrent files, and give categories
  their own folders.
- Create torrents from a file or folder (⇧⌘N), and read the engine's log (⇧⌘L).
- Settings for unfinished-download folders, watched folders, skipped file names, commands to
  run on add or finish, a speed schedule, network interface binding, encryption, proxy, DHT/PeX/LSD
  and IP filter lists.

## Requirements

- macOS 26 or later
- Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A `qbittorrent-nox` build (see below)

## Build the engine

```sh
brew install cmake ninja libtorrent-rasterbar qtbase qttools
git clone https://github.com/qbittorrent/qBittorrent.git --branch release-5.3.0 qbt-engine-src
cmake -S qbt-engine-src -B qbt-engine-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGUI=OFF -DWEBUI=ON -DSTACKTRACE=OFF -DCMAKE_PREFIX_PATH=/opt/homebrew
ninja -C qbt-engine-build
scripts/bundle-engine.sh path/to/qbt-engine-build/qbittorrent-nox.app
```

`scripts/bundle-engine.sh` makes the engine self-contained in `build/engine/qbittorrent-nox.app`:
it copies in Qt, libtorrent and OpenSSL with `macdeployqt`, removes the GUI-only parts, points
library lookup inside the bundle, and signs every binary. It fails if anything still links
outside the bundle. Set `SIGN_IDENTITY` to a Developer ID to sign with the hardened runtime.
The bundle is Apple silicon only for now.

## Build the app

```sh
xcodegen generate
xcodebuild -project Sprout.xcodeproj -scheme Sprout build
```

`scripts/embed-engine.sh` copies the engine bundle into `Sprout.app/Contents/Helpers`.
Set `QBT_ENGINE_APP` to use a bundle somewhere other than `build/engine`.

## How the engine is run

- Profile: `~/Library/Application Support/Sprout/Engine` (log: `engine.log` there).
- The Web API listens on `127.0.0.1` only, on a free port chosen at each launch.
- Sprout writes a random API key into the engine's config and sends it as a bearer token.
  Localhost authentication stays on, so other programs can't drive the engine without it.
- Quitting Sprout asks the engine to save resume data and exit. Closing the window does not
  quit: torrents keep running, like other Mac clients.
- Sprout records the engine's process ID. If Sprout crashes and leaves the engine running,
  the next launch asks that engine to save and quit before starting a new one.

## Icon

`Resources/Sprout.icon` is an Icon Composer icon drawn by `scripts/make-icon.py`: a seedling in
lit dots over a seed bed, on the app's black LED panel, with one orange dot for new growth.
Edit the pattern in the script and run it again; `--preview out.png` writes a flat preview.

## Licence

Sprout is free software under the GNU GPL, version 3 or later (see `LICENSE`). The app bundles
qBittorrent's engine, unmodified, and the libraries it needs: Qt (LGPL v3), libtorrent, Boost,
OpenSSL, ICU, GLib and gettext's libintl (LGPL v2.1), PCRE2, Zstandard, Brotli,
double-conversion and libb2. Their licence texts are in `Resources/Licenses` and inside the app,
and the About window lists each with its version and source.

## Not done yet

- Notarized release: `scripts/release.sh` is ready but has not produced a release yet.
- Intel Macs: the engine bundle is Apple silicon only.
- Importing torrents from another client.

## Licence

GPL-3.0-or-later. Sprout bundles a qBittorrent engine binary, which is distributed under
GPLv3+. See `LICENSE`.
