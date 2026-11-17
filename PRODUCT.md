# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app (SwiftUI with AppKit where SwiftUI falls short). Not one of the schema's web/ios/android values; Apple HIG for macOS governs.

## Stack

SwiftUI app, minimum macOS 26 (Liquid Glass only, no fallback styling). The torrent engine is qBittorrent's headless `qbittorrent-nox` (C++/Qt/libtorrent), bundled inside the app and driven over its local Web API v2.

## Users

Mac users who want qBittorrent's engine and features in an app that behaves like a real Mac app, instead of the cross-platform Qt interface. Typical job: add a magnet link or .torrent file, watch it download, manage what is downloading or seeding.

## Product Purpose

A fully native macOS front end for qBittorrent that replaces the Qt desktop app on a Mac. Success: a Mac user can install one app, open magnets and .torrent files from the browser or Finder, and never need the Qt UI.

## Positioning

Bundles and manages the real qBittorrent engine, so it is a standalone desktop client, not just a remote control. Existing native Mac qBittorrent clients (Dreadnought, Drift; checked 2026-11-17) are remote Web API clients only and are small or experimental.

## Operating Context

- Torrents are added from browser magnet links, downloaded .torrent files, Finder, or drag and drop.
- Long-running: downloads run for hours; the app is glanced at, not stared at.
- Lives alongside other Mac apps: Dock, menu bar, notifications, Finder.

## Capabilities and Constraints

v1 scope (confirmed):
- Bundled engine, started and stopped by the app.
- Add magnets and .torrent files; list torrents with progress and speeds; start, stop, remove; filter by state.
- Torrent inspector: files (with priorities), peers, trackers, general info.

Not in v1: connecting to remote qBittorrent instances, RSS, search plugins.

Constraints:
- Licence: GPL-3.0-or-later, because it bundles a qBittorrent engine binary (qBittorrent binaries are GPLv3+). Source is public.
- Distribution: free download, notarized; Mac App Store not planned.
- Engine terms follow qBittorrent's Web API: torrents are "started"/"stopped" (5.x wording), not "paused".

Undecided: product name (working folder name `torrent-mac`).

## Brand Commitments

None yet. Must not present itself as an official qBittorrent product.

## Evidence on Hand

None. No users, testimonials or benchmarks exist; do not fabricate any.

## Product Principles

1. Behave like a Mac app first: standard windows, menus, keyboard shortcuts, drag and drop, system integration.
2. The engine is invisible: users never configure ports or passwords to make the app work.
3. Glanceable: state and speed are readable at a glance from across a long download.
4. Keep qBittorrent's power reachable without putting it all on the first screen.
