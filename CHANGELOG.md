# Changelog

All notable changes to paw. Versions follow [Semantic Versioning](https://semver.org); entries
come from [Conventional Commits](https://www.conventionalcommits.org) via release-please.

## [0.1.0-beta.2](https://github.com/pseudobun/paw/compare/v0.1.0-beta.1...v0.1.0-beta.2) (2026-11-10)


### ⚠ BREAKING CHANGES

* the bundle id is now com.pseudobun.paw (was dev.paw.app); Accessibility must be granted again.
* paw no longer reads yabai; the yabai config section is gone.
* hint, search and scroll modes and their config are removed.

### Features

* add a displaysChanged hook ([68efc1e](https://github.com/pseudobun/paw/commit/68efc1e3d6dff991627e6521cda333bb5fc202b2))
* add a low-poly bunny paw app icon in hop's style ([e7910ca](https://github.com/pseudobun/paw/commit/e7910caa13a425c071cd0b2f885ea9c98d17fb93))
* add hint, search and scroll modes with sketchybar-style labels ([16f3b04](https://github.com/pseudobun/paw/commit/16f3b04553fbac6683d4f5ba18d62f9916a6c095))
* add initiate, arrange all and a windowsChanged hook ([b94f4c7](https://github.com/pseudobun/paw/commit/b94f4c7f83b09b70711a1fded3418c45d6f6af47))
* add key modes with a resize mode on hyper+r ([696c80e](https://github.com/pseudobun/paw/commit/696c80e28b33063168aeba15661e6e65d0c50b0d))
* add overview, weighted tree, drop zones and event stream ([e9f5443](https://github.com/pseudobun/paw/commit/e9f54433fbe215f12a3d0daf0eefd41a6418697a))
* add setups per display arrangement and a settings window ([3055eb3](https://github.com/pseudobun/paw/commit/3055eb3c67cd7b983f2295103556b530b93b9edf))
* add Sparkle updates and release-please releases ([258cb18](https://github.com/pseudobun/paw/commit/258cb186b1cfecfbc7cda9e1c8dda694dd43eaca))
* add Sparkle updates and release-please releases ([f850b63](https://github.com/pseudobun/paw/commit/f850b635c6086ff1939f29e2123bb770b23010f0))
* add swap stack.next|stack.prev to reorder a stack ([cc5857f](https://github.com/pseudobun/paw/commit/cc5857f4c35567f45814517f3d0172c46aa83eb9))
* add the paw app icon and menu bar symbol ([4ca0af6](https://github.com/pseudobun/paw/commit/4ca0af6bd209109223cb9f60419631877f2db0e7))
* colour app icons with each app's own colour ([c861309](https://github.com/pseudobun/paw/commit/c8613093ee3678e42db8e78b07a9a1fa0fea339c))
* **indicators:** add indicator.enabled to turn stack indicators off ([9509b97](https://github.com/pseudobun/paw/commit/9509b97cb5ee36bde4b0cb5145f28773524be090))
* **indicators:** add indicator.enabled to turn stack indicators off ([fb45801](https://github.com/pseudobun/paw/commit/fb45801afd4f55c2d1955e425736f90f692c95f8))
* **indicators:** show the app's own icon when the font has no glyph ([5e7cd8d](https://github.com/pseudobun/paw/commit/5e7cd8dd5e59c28d9e79c76115fc41b09a6318e2))
* **layout:** make placeholders optional and give them a minimum size ([422070b](https://github.com/pseudobun/paw/commit/422070bb6791dd3d3ba2d6f4f3a3567e14dc140e))
* **layout:** make placeholders optional and give them a minimum size ([056138e](https://github.com/pseudobun/paw/commit/056138e28e717e8abce5dea280a6e63ebd969f80))
* replace keyboard clicking with yabai stack indicators ([b11dc34](https://github.com/pseudobun/paw/commit/b11dc34d864044d13c0a987772b9ab60557b17ba))
* retile on display changes and stop stack cycling at the ends ([f190484](https://github.com/pseudobun/paw/commit/f190484ea985a254171be71946d82dd5624fc6af))
* **settings:** rebuild the settings window in hop's style ([8370050](https://github.com/pseudobun/paw/commit/83700509bf2aa275c866cf2026e38163d847d09e))
* turn paw into a tiling window manager with virtual workspaces ([53e075d](https://github.com/pseudobun/paw/commit/53e075dfad074542b79f273989245ec85a6befa5))


### Bug Fixes

* **bundle:** keep going when the keychain has no signing identity ([1057371](https://github.com/pseudobun/paw/commit/1057371647f2b4769fa80207d10cedc4404dbd1a))
* **bundle:** keep going when the keychain has no signing identity ([c4491eb](https://github.com/pseudobun/paw/commit/c4491ebfaae706ca8fb07fc739f2bbc6cded5805))
* **bundle:** pick the signing identity without SIGPIPE ([35831fd](https://github.com/pseudobun/paw/commit/35831fd7eea4c5b90e6a78dc8fb61056b716ee7a))
* **bundle:** prefer a Developer ID identity over Apple Development ([63ed796](https://github.com/pseudobun/paw/commit/63ed7967b171c5236010a948dbf717d210435289))
* **bundle:** sign with the certificate's hash, not its name ([5249781](https://github.com/pseudobun/paw/commit/5249781ff7d3b40eab60383a2c943762389cf0f8))
* draw stack indicators upright and see hyper from key remappers ([f374709](https://github.com/pseudobun/paw/commit/f37470991009ce1c20b91a91640c6f6f35df7e7e))
* drop windows that close without a notification ([641623e](https://github.com/pseudobun/paw/commit/641623e48a87195180e3e914a70b1ef1dc52e46f))
* **examples:** restart sketchybar after every display change ([89b0772](https://github.com/pseudobun/paw/commit/89b07726297791824bff770424cf641a4d0fe5ac))
* **examples:** restart sketchybar when it settles on the wrong displays ([93d4d20](https://github.com/pseudobun/paw/commit/93d4d203dc148a29314ac92a8ff9af8e4348739c))
* **examples:** restart sketchybar without waiting for it to see the displays ([21ee3e9](https://github.com/pseudobun/paw/commit/21ee3e9d40d43a4bbce2305203d06cc9c8ea324e))
* **ipc:** replace distributed notifications with a user-only unix socket ([3d36900](https://github.com/pseudobun/paw/commit/3d36900306e739b35eb7701e6cca2f060d712c3f))
* **just:** stop only the app on install, not paw CLI processes ([5e06046](https://github.com/pseudobun/paw/commit/5e060468762753186e7f5d817f97542b61b06436))
* keep every tile at least the placeholder size when resizing ([214b31d](https://github.com/pseudobun/paw/commit/214b31df71e6cbc37a58153c767e3dbf1d923a33))
* keep every tile at least the placeholder size when resizing ([4c9b3f8](https://github.com/pseudobun/paw/commit/4c9b3f8163225ece9b9975ea0ecb20ed75aaaaca))
* keep one paw running when open and launchd start it together ([94c8662](https://github.com/pseudobun/paw/commit/94c8662fd264ab4cff76d816f3e30fd18af6d887))
* manage menu bar apps that turn regular after launch ([685c222](https://github.com/pseudobun/paw/commit/685c222bfe305c0ec53bb2585b4ae911a1142051))
* move a window dragged onto another display to that display's workspace ([cd606da](https://github.com/pseudobun/paw/commit/cd606da41fc09761207b8978d493deed40251dc6))
* open an app's new window on the workspace where you already use it ([4ca3a7f](https://github.com/pseudobun/paw/commit/4ca3a7f686e35291935c0ab231b8123c5c3ca04a))
* retile sooner after a display is unplugged ([2c03c32](https://github.com/pseudobun/paw/commit/2c03c3203c521fd1968f942a53cf71628f543f26))
* **updates:** check without Sparkle's modal alerts ([312b63a](https://github.com/pseudobun/paw/commit/312b63ace8fe5a1a3915d2aaf0eff6a969081f92))
* **updates:** check without Sparkle's modal alerts ([4b5a412](https://github.com/pseudobun/paw/commit/4b5a4123389d7454a4c6c0a9319b3c6408eba4fb))
* wait for displays to settle before retiling ([67b46e6](https://github.com/pseudobun/paw/commit/67b46e6b9f18540d4bf5fd4c3ce31b5af01381a7))
* wait for unplugged displays to settle too ([3555f86](https://github.com/pseudobun/paw/commit/3555f861cbfc54335503ca9ad8635c0f24980eb3))


### Performance

* strip the release binary and answer CLI requests without polling ([5348999](https://github.com/pseudobun/paw/commit/534899950d8b3574b4de6e044a1b186654a50a66))


### Reverts

* drop the generated paw app icon ([d11c58c](https://github.com/pseudobun/paw/commit/d11c58c375d8cdf1211d51a87ed594aaee248f75))


### Miscellaneous

* prepare paw for open source as 0.1.0-beta.1 ([42bb42a](https://github.com/pseudobun/paw/commit/42bb42abe26dddb2b4cb565e7b3666232ee83298))

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
- Homebrew cask: `brew install --cask pseudobun/tap/paw`
- Updates through Sparkle: a daily check that offers new versions (`updates.check`), silent
  installs if you want them (`updates.automatic`), "Check for Updates…" in the menu bar and
  `paw update`

### Changed

- Bundle identifier is now `com.pseudobun.paw` (was `dev.paw.app`). Grant Accessibility again
  after upgrading from a local build; `just install` moves the old state over
