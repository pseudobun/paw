# Security policy

## Supported versions

paw is in beta. Only the latest release gets security fixes; it updates itself
(`paw update`), or run `brew upgrade --cask pseudobun/tap/paw`.

## What paw trusts

- **Anything running as you can drive paw.** Its socket (`~/Library/Application
  Support/com.pseudobun.paw/paw.sock`, mode 0600) accepts any process of the same user, and
  paw can do everything it has permission for: move, focus and hide any window, read window
  titles, and run commands (`paw run 'exec …'`). A process without Accessibility can ask paw
  to do what Accessibility allows. Run only software you trust as your user; sandboxed apps
  can't reach the socket.
- **The Dock helper runs as root and inside Dock.** It is optional (`sudo paw dock install`),
  needs SIP's debugging restrictions off, and loads only a payload that is owned by root and
  writable by no one else. Remove it with `sudo paw dock uninstall` before uninstalling paw.

## Reporting a vulnerability

Please don't open a public issue. Report it privately:

- on GitHub: **Security → Report a vulnerability**
  (<https://github.com/pseudobun/paw/security/advisories/new>), or
- by email to **urban@bunnys.cloud**.

Include the paw version (`paw version`), your macOS version, the steps to reproduce and what
an attacker gains. You'll hear back within a few days; once a fix is released the advisory is
published with credit, unless you'd rather stay anonymous.
