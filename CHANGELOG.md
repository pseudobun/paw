# Changelog

All notable changes to paw. Versions follow [Semantic Versioning](https://semver.org); entries
come from [Conventional Commits](https://www.conventionalcommits.org) via release-please.

## [0.1.0](https://github.com/pseudobun/paw/compare/v0.1.0-beta.16...v0.1.0) (2026-11-13)


### Features

* **hud:** glide the edge markers to a new neighbour like the tip bar's islands ([#90](https://github.com/pseudobun/paw/issues/90)) ([cd44400](https://github.com/pseudobun/paw/commit/cd44400879ca9dafe57c5c0ef38b8e4ca7324fbd))
* **hud:** glide the edge markers to a new neighbour like the tip bar's islands ([#91](https://github.com/pseudobun/paw/issues/91)) ([38fd059](https://github.com/pseudobun/paw/commit/38fd059aaa2dd9efe959a667be22cfa794654c7c))
* **hud:** slide the workspace HUD and edge markers the way the workspace went ([d7ada60](https://github.com/pseudobun/paw/commit/d7ada6077ec9c2a12ba197dce38d0f63d7bf05f0))
* **hud:** slide the workspace HUD and edge markers the way the workspace went ([442c648](https://github.com/pseudobun/paw/commit/442c648282763b8eb5376c362e5766cc6f45154c))
* **indicator:** cross-fade stack cells on change like the bar's spaces ([b47c758](https://github.com/pseudobun/paw/commit/b47c758ed430e21c5e99e93ce6333b1d6d8c798e))
* **indicator:** cross-fade stack cells on change like the bar's spaces ([193d157](https://github.com/pseudobun/paw/commit/193d157c8eefb7df895d60056cf037c37a101df7))
* **indicator:** glide the stack highlight to the window on top like the tip bar ([#87](https://github.com/pseudobun/paw/issues/87)) ([cc5aac8](https://github.com/pseudobun/paw/commit/cc5aac8df6bae51e89fef5a372e704c0594c9247))
* **indicator:** glide the stack highlight to the window on top like the tip bar ([#88](https://github.com/pseudobun/paw/issues/88)) ([3229156](https://github.com/pseudobun/paw/commit/3229156284fd113f986758ca6ffb5cfadc82b9ec))
* **indicator:** show app icons without the app font and cross-fade stack cells ([#78](https://github.com/pseudobun/paw/issues/78)) ([b736ae1](https://github.com/pseudobun/paw/commit/b736ae165234c0e795e6c127a864fd4e073bd317))
* **indicator:** show app icons without the app font and cross-fade stack cells ([#79](https://github.com/pseudobun/paw/issues/79)) ([4dbb653](https://github.com/pseudobun/paw/commit/4dbb653d8ab79375921b054394837ad05217610d))
* **setups:** make switching setups on display changes optional ([#74](https://github.com/pseudobun/paw/issues/74)) ([7646592](https://github.com/pseudobun/paw/commit/7646592ca4020bda5cc33fd71b493cb73ec75ad2))
* **setups:** make switching setups on display changes optional ([#75](https://github.com/pseudobun/paw/issues/75)) ([1180e8e](https://github.com/pseudobun/paw/commit/1180e8e7270168b08f2bbf928068ae588bbe87ab))
* **ui:** add liquid glass design ([#93](https://github.com/pseudobun/paw/issues/93)) ([56e8bf8](https://github.com/pseudobun/paw/commit/56e8bf8313aa728ef16d2d1189fed09571a2437e))
* **ui:** make liquid glass more see-through and configurable ([#107](https://github.com/pseudobun/paw/issues/107)) ([4e061cf](https://github.com/pseudobun/paw/commit/4e061cf78a4cb52dd445bff3f2c9b8dbc61f61ad))
* **updates:** add a beta channel and release betas from a beta branch ([#61](https://github.com/pseudobun/paw/issues/61)) ([da07dbd](https://github.com/pseudobun/paw/commit/da07dbd13c2be9975843273de223af651cc2e1be))


### Bug Fixes

* **border:** hide focus border while dragging or resizing a window ([#60](https://github.com/pseudobun/paw/issues/60)) ([bfb525c](https://github.com/pseudobun/paw/commit/bfb525c6c2fb1fe9ae6edce03364c5f6d66b4c56))
* **bundle:** don't fail when PackageFrameworks is missing ([#62](https://github.com/pseudobun/paw/issues/62)) ([18698a9](https://github.com/pseudobun/paw/commit/18698a9f56adf312db29c904e0bfb5525816cffc))
* **cask:** name the conflicting cask with its tap ([#81](https://github.com/pseudobun/paw/issues/81)) ([19fc0c1](https://github.com/pseudobun/paw/commit/19fc0c1f3411ce7918df1a22e3f0cc5b23612b18))
* **cask:** name the conflicting cask with its tap ([#82](https://github.com/pseudobun/paw/issues/82)) ([e31e3e1](https://github.com/pseudobun/paw/commit/e31e3e149a497499773c4c6ccc303a6c53a2356b))
* **config:** apply every setting on live reload and surface broken configs ([#108](https://github.com/pseudobun/paw/issues/108)) ([7e16c8b](https://github.com/pseudobun/paw/commit/7e16c8b530ca6f4ba896e783ceb85a6ed57824e1))
* **float:** keep fixed-size and floating windows usable ([#63](https://github.com/pseudobun/paw/issues/63)) ([1795563](https://github.com/pseudobun/paw/commit/179556398dfefb7743e2035b5c76beb46e122741))
* **float:** keep tiled parents below floating windows ([#76](https://github.com/pseudobun/paw/issues/76)) ([fd8f959](https://github.com/pseudobun/paw/commit/fd8f9591d7d4720819d46acd0aac551fd41cf5a7))
* **hud:** keep island content centred while a glass island glides ([789b7ed](https://github.com/pseudobun/paw/commit/789b7ed05a6173af4afb4e3c0a54e5ed3e89ada0))
* **hud:** keep island content centred while a glass island glides ([20c89e4](https://github.com/pseudobun/paw/commit/20c89e4a8f26b42537b1f9f86fd372575fafa511))
* **indicator:** draw app icons in edge markers without the app font ([#84](https://github.com/pseudobun/paw/issues/84)) ([a6f55c7](https://github.com/pseudobun/paw/commit/a6f55c7de16fb74ccf742bf5e7597c0f9df1cd8e))
* **indicator:** draw app icons in edge markers without the app font ([#85](https://github.com/pseudobun/paw/issues/85)) ([76becdc](https://github.com/pseudobun/paw/commit/76becdcb61ae06d2a3626641bdcd740ef77d6c0b))
* **indicator:** show app icons instead of initials without the app font ([63656aa](https://github.com/pseudobun/paw/commit/63656aaee3c979d7a1401cf551a2fdb5f5b04ecd))
* **indicator:** show app icons instead of initials without the app font ([d5e6306](https://github.com/pseudobun/paw/commit/d5e630638ee145798a137077b1979ddc88471029))
* **layout:** put windows an app shrank right after placing back on their tile ([#72](https://github.com/pseudobun/paw/issues/72)) ([6b3d065](https://github.com/pseudobun/paw/commit/6b3d06588626a54fd3901340cdb060ac4ef728c1))
* **settings:** offer only the beta channel until a stable version exists ([#66](https://github.com/pseudobun/paw/issues/66)) ([eff1d57](https://github.com/pseudobun/paw/commit/eff1d574e5939612dc81635a3ab4719914e57c98))
* **settings:** offer only the beta channel until a stable version exists ([#67](https://github.com/pseudobun/paw/issues/67)) ([aaef1fd](https://github.com/pseudobun/paw/commit/aaef1fdcf628524ceb4264f5c2fbd0beb29f88f4))
* **wm:** leave self-floating panels like Ghostty's quick terminal alone ([1e67994](https://github.com/pseudobun/paw/commit/1e67994f25f66b346f5f7f65ff566e64424ec214))


### Performance

* **overview:** reuse closed overview panels ([#99](https://github.com/pseudobun/paw/issues/99)) ([4c766e0](https://github.com/pseudobun/paw/commit/4c766e0fbc9ebf66bd2eec4e9312d61880a4e0bd))
* **state:** skip rewriting an unchanged state file ([#97](https://github.com/pseudobun/paw/issues/97)) ([d08d4dc](https://github.com/pseudobun/paw/commit/d08d4dc5ea3742003b47904c8b12268faeb99a8e))
* **wm:** read live window numbers without bridging descriptions ([#96](https://github.com/pseudobun/paw/issues/96)) ([2d08fa8](https://github.com/pseudobun/paw/commit/2d08fa8c47a74b809ec8d51efad09611c9b486c7))

## [0.1.0-beta.16](https://github.com/pseudobun/paw/compare/v0.1.0-beta.15...v0.1.0-beta.16) (2026-11-12)


### Bug Fixes

* **cask:** only quit paw on upgrade ([9141c0e](https://github.com/pseudobun/paw/commit/9141c0eb426411eee50a072f73f9d916ab30ee0d))
* **focus:** select revealed tiles and restore placeholder shortcuts ([#57](https://github.com/pseudobun/paw/issues/57)) ([e2c6d35](https://github.com/pseudobun/paw/commit/e2c6d35732146e6bedc6589a0627dd116eced260))
* **wm:** ignore pop-up menu windows such as Qt context menus ([#59](https://github.com/pseudobun/paw/issues/59)) ([6e9434f](https://github.com/pseudobun/paw/commit/6e9434f93d5e0d0b7d7538c94c1a7675e5c86ac8))

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
