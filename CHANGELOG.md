# Changelog

All notable changes to paw. Versions follow [Semantic Versioning](https://semver.org); entries
come from [Conventional Commits](https://www.conventionalcommits.org) via release-please.

## [0.1.0-beta.15](https://github.com/pseudobun/paw/compare/v0.1.0-beta.14...v0.1.0-beta.15) (2026-11-11)


### Bug Fixes

* **cask:** keep the Dock helper out of upgrades ([aec235b](https://github.com/pseudobun/paw/commit/aec235b5c2b33294df523cd5f817d106798f0e74))
* **dock:** note a changed Dock helper instead of asking for admin access ([261bfb1](https://github.com/pseudobun/paw/commit/261bfb1631f346285defd2c9fe64925cd5ced7a0))

## [0.1.0-beta.14](https://github.com/pseudobun/paw/compare/v0.1.0-beta.13...v0.1.0-beta.14) (2026-11-11)


### Features

* **dock:** install the changed Dock helper after an update ([0ac7aa1](https://github.com/pseudobun/paw/commit/0ac7aa1270d00f9b5fdd7085451c6c46b7d2b37c))
* **dock:** version the Dock helper and restart Dock when it changes ([884f4a1](https://github.com/pseudobun/paw/commit/884f4a1bc6f2281a78eafe0abbcfa1aaa3c01a54))


### Bug Fixes

* **focus:** prefer hovered window after closing focused window ([#51](https://github.com/pseudobun/paw/issues/51)) ([b67b6c5](https://github.com/pseudobun/paw/commit/b67b6c5f4dd4905278eacdfad6251ffcd23b0eca))
* match focus borders to window corners and cache updates ([#49](https://github.com/pseudobun/paw/issues/49)) ([5738b73](https://github.com/pseudobun/paw/commit/5738b736f235b1bd52991d383a03e559c0890e54))

## [0.1.0-beta.13](https://github.com/pseudobun/paw/compare/v0.1.0-beta.12...v0.1.0-beta.13) (2026-11-11)


### Features

* add `join` to move a window into its neighbour's tile as a row ([6fe1364](https://github.com/pseudobun/paw/commit/6fe1364cce0bd59151b0db84a342c5b02b0b111c))
* add indicator themes and a live preview in Settings ([#50](https://github.com/pseudobun/paw/issues/50)) ([26143e2](https://github.com/pseudobun/paw/commit/26143e23a9e5e3f19cc33fa416cc8aa853b95374))


### Bug Fixes

* **dock:** harden the Dock helper and its uninstall ([bc4b41e](https://github.com/pseudobun/paw/commit/bc4b41e8b2aed52311dfd29c28faf434c915f401))
* **dock:** restart the helper daemon in place when reinstalling ([#46](https://github.com/pseudobun/paw/issues/46)) ([442a519](https://github.com/pseudobun/paw/commit/442a5191abf930eda7cc6977dc948e8d4082512e))
* **focus:** prevent hover focus through native dialogs ([#48](https://github.com/pseudobun/paw/issues/48)) ([efc0e10](https://github.com/pseudobun/paw/commit/efc0e1016ee0166a6cab9add45d9342e93117717))


### Performance

* keep the main thread off slow apps and cut redraw work ([#52](https://github.com/pseudobun/paw/issues/52)) ([8b00024](https://github.com/pseudobun/paw/commit/8b0002483091cbd485fb25157d0006ddbea4dd28))

## [0.1.0-beta.12](https://github.com/pseudobun/paw/compare/v0.1.0-beta.11...v0.1.0-beta.12) (2026-11-11)


### Features

* switch workspaces faster and show the neighbouring workspaces ([#44](https://github.com/pseudobun/paw/issues/44)) ([4caac46](https://github.com/pseudobun/paw/commit/4caac46e426b83da0ed96ce7a6259fe67d60f352))

## [0.1.0-beta.11](https://github.com/pseudobun/paw/compare/v0.1.0-beta.10...v0.1.0-beta.11) (2026-11-11)


### Bug Fixes

* **zoom:** stop windows gliding across neighbouring displays ([#42](https://github.com/pseudobun/paw/issues/42)) ([5b1b548](https://github.com/pseudobun/paw/commit/5b1b548cc08414f0ac536aba2f209c1fabf6c1ad))

## [0.1.0-beta.10](https://github.com/pseudobun/paw/compare/v0.1.0-beta.9...v0.1.0-beta.10) (2026-11-11)


### Bug Fixes

* **zoom:** move focus to the next display at the edge of a zoom ([#40](https://github.com/pseudobun/paw/issues/40)) ([fdfd44c](https://github.com/pseudobun/paw/commit/fdfd44c7ecdada8fa4516ea3fff6056cb6d7beeb))

## [0.1.0-beta.9](https://github.com/pseudobun/paw/compare/v0.1.0-beta.8...v0.1.0-beta.9) (2026-11-11)


### Bug Fixes

* **zoom:** keep directional focus inside a zoom and report the zoom level ([#38](https://github.com/pseudobun/paw/issues/38)) ([f3239f0](https://github.com/pseudobun/paw/commit/f3239f0f48c0fe7844c11343b20931d229cb39b7))

## [0.1.0-beta.8](https://github.com/pseudobun/paw/compare/v0.1.0-beta.7...v0.1.0-beta.8) (2026-11-10)


### Features

* **dev:** build from source as paw Dev, next to the release paw ([#35](https://github.com/pseudobun/paw/issues/35)) ([67f9443](https://github.com/pseudobun/paw/commit/67f944371f144280d245ec0c1a39c20580a929ff))

## [0.1.0-beta.7](https://github.com/pseudobun/paw/compare/v0.1.0-beta.6...v0.1.0-beta.7) (2026-11-10)


### Bug Fixes

* recover placeholders when window minimums shrink ([#29](https://github.com/pseudobun/paw/issues/29)) ([79f7904](https://github.com/pseudobun/paw/commit/79f79043bd7a5adf535610e8f13587afe3eb9eca))

## [0.1.0-beta.6](https://github.com/pseudobun/paw/compare/v0.1.0-beta.5...v0.1.0-beta.6) (2026-11-10)


### Features

* **updates:** update silently in the background ([#32](https://github.com/pseudobun/paw/issues/32)) ([9a4a577](https://github.com/pseudobun/paw/commit/9a4a577fde31e23fec13c5548a889f3804749430))


### Bug Fixes

* address the 2026-11-10 security audit ([#27](https://github.com/pseudobun/paw/issues/27)) ([c00f134](https://github.com/pseudobun/paw/commit/c00f134ba1104dd955150940ff2ff2f18fc34d11))
* focus placeholders when following the mouse ([#30](https://github.com/pseudobun/paw/issues/30)) ([d24c8ce](https://github.com/pseudobun/paw/commit/d24c8ced383c8094184965378db97cd611b9e645))
* raise restored placeholders after toggling full screen ([#31](https://github.com/pseudobun/paw/issues/31)) ([e043891](https://github.com/pseudobun/paw/commit/e0438911d82b730d3b8f274efbb20ac0af7418bf))

## [0.1.0-beta.5](https://github.com/pseudobun/paw/compare/v0.1.0-beta.4...v0.1.0-beta.5) (2026-11-10)


### Bug Fixes

* **cask:** mark paw as self-updating with auto_updates ([#25](https://github.com/pseudobun/paw/issues/25)) ([aa39cc9](https://github.com/pseudobun/paw/commit/aa39cc92b7b90026047ce995247360f14997064f))

## [0.1.0-beta.4](https://github.com/pseudobun/paw/compare/v0.1.0-beta.3...v0.1.0-beta.4) (2026-11-10)


### Features

* **settings:** add an About page with the version, links and an author footer ([3d81699](https://github.com/pseudobun/paw/commit/3d81699dc908e72a422b2596566b0c65e4770062))


### Bug Fixes

* **cask:** use the current depends_on macos syntax ([#23](https://github.com/pseudobun/paw/issues/23)) ([d12e1f2](https://github.com/pseudobun/paw/commit/d12e1f210780d68b8823bccc71b2607e70e1b86f))
* **overview:** show every app of a stack on the workspace cards ([#21](https://github.com/pseudobun/paw/issues/21)) ([2b88d23](https://github.com/pseudobun/paw/commit/2b88d2397e42f2a66312d2633c6c8f6210eddd33))

## [0.1.0-beta.3](https://github.com/pseudobun/paw/compare/v0.1.0-beta.2...v0.1.0-beta.3) (2026-11-10)


### Features

* **overview:** add a canvas mode with every workspace side by side ([#18](https://github.com/pseudobun/paw/issues/18)) ([654a156](https://github.com/pseudobun/paw/commit/654a156eb2350f3cfec27c3e4f0826f1b8d99743))
* **settings:** show permissions with request buttons; fix the update window ([#20](https://github.com/pseudobun/paw/issues/20)) ([4986b5a](https://github.com/pseudobun/paw/commit/4986b5abd877bbc1e0e35ecbe3bafb05e646e5c9))

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
