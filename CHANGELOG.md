# Changelog

All notable changes to paw. Versions follow [Semantic Versioning](https://semver.org); entries
come from [Conventional Commits](https://www.conventionalcommits.org) via release-please.

## [0.1.0-beta.2](https://github.com/pseudobun/paw/compare/v0.1.0-beta.1...v0.1.0-beta.2) (2026-11-10)


### Features

* mark the ends of the move strip with an empty start/end slot ([#17](https://github.com/pseudobun/paw/issues/17)) ([90bc0cf](https://github.com/pseudobun/paw/commit/90bc0cfd359ef7338a04a550d8daa814c3120f48))
* show where a moving workspace is; stop workspace next/prev at the ends ([#16](https://github.com/pseudobun/paw/issues/16)) ([2397781](https://github.com/pseudobun/paw/commit/239778164db158679cc7c3a84944ed6186cd1635))

## [0.1.0-beta.1](https://github.com/pseudobun/paw/releases/tag/v0.1.0-beta.1) (2026-11-10)

First public beta.

### Added

- Tiling layouts per workspace: `bsp`, `columns`, `master`, `stack` and `float`, on a weighted
  tree where a split holds any number of tiles
- Stacks with indicator islands: one app icon per window in the app's own colour; click, scroll
  and hover
- Virtual workspaces that replace macOS Spaces, without SIP changes
- Workspace presets, setups per display arrangement, `arrange` and `initiate`
- Drop zones and seam handles for the mouse, mouse gestures, focus border
- Overview of every workspace and window (`hyper+tab`), with live pictures when Screen
  Recording is allowed
- Zoom through the tree, canvas mode, undo/redo, focus history and `find`
- Key bindings and key modes in a commented JSON5 config, plus a Settings window
- A CLI for every command over a private Unix socket, and `paw subscribe` for status bars
- Placeholders for windows whose app won't shrink to their tile (`layout.placeholders`), and a
  smallest tile size when resizing (`layout.placeholderMinWidth`/`Height`)
- `indicator.enabled` to turn the stack indicators off
- Windows of an unplugged display go to their preset workspace, or wait on a side workspace
  (`+N` in the bar) until you sort them
- Move a whole workspace to another display, or its contents along the workspaces
- Homebrew cask: `brew install --cask pseudobun/tap/paw`
- Updates through Sparkle: a daily check that offers new versions (`updates.check`), silent
  installs if you want them (`updates.automatic`), "Check for Updates…" in the menu bar and
  `paw update`

### Changed

- Bundle identifier is now `com.pseudobun.paw` (was `dev.paw.app`). Grant Accessibility again
  after upgrading from a local build; `just install` moves the old state over
