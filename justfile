# paw: build, test and run a dev build next to the release one. Signing is picked by
# scripts/bundle.sh (Apple Development identity → "paw Local Signing" → ad-hoc).
#
# The release paw comes from Homebrew (brew install --cask pseudobun/tap/paw): /Applications/paw.app,
# com.pseudobun.paw, CLI `paw`. `just dev` builds "paw Dev" (com.pseudobun.paw.dev, own data and
# grants, no updates, no login item) into ~/Applications, quits the release paw and starts the dev
# one; `just undev` goes back. `paw` finds whichever runs; `paw-dev` is the dev build's own CLI.

dev_app := env("HOME") / "Applications/paw Dev.app"
dev_cli := "/opt/homebrew/bin/paw-dev"
release_id := "com.pseudobun.paw"
local_identity := "paw Local Signing"
launch_agent := env("HOME") / "Library/LaunchAgents/com.pseudobun.paw.plist"

default: build

# Debug build (.build/debug/paw)
build:
    swift build

# Unit tests (layout tree, commands, key bindings, placement, config, icon map)
test:
    swift test

# Release-configuration paw.app into ./build.noindex (.noindex keeps Spotlight from listing a second paw)
bundle:
    scripts/bundle.sh build.noindex

# Build "paw Dev", quit the release paw and run the dev one instead
dev:
    PAW_DEV=1 scripts/bundle.sh build.noindex/dev
    @just _quit
    rm -rf "{{dev_app}}"
    mkdir -p "$(dirname "{{dev_app}}")"
    cp -R build.noindex/dev/paw.app "{{dev_app}}"
    ln -sf "{{dev_app}}/Contents/MacOS/paw" "{{dev_cli}}"
    open "{{dev_app}}"
    @echo "running {{dev_app}} (CLI: paw-dev); just undev goes back to the release paw"

# Quit the dev build and start the release paw again
undev:
    @just _quit
    open -b {{release_id}}

# The old name: builds and runs the dev build, never touches the release paw
install: dev

# Remove the dev build (the release paw stays; brew uninstall --cask pseudobun/tap/paw removes it)
uninstall:
    @just _quit
    rm -rf "{{dev_app}}" "{{dev_cli}}"
    -open -b {{release_id}}

# Quits every paw.app (release and dev); paw puts hidden windows back first.
# `MacOS/paw$` spares CLI processes such as a bar's `paw subscribe`.
_quit:
    -paw quit 2>/dev/null; paw-dev quit 2>/dev/null; true
    @for i in $(seq 1 50); do pgrep -f 'MacOS/paw$' >/dev/null || break; sleep 0.1; done
    -pkill -f 'MacOS/paw$'

# Self-signed code-signing certificate (stable signature across rebuilds)
local-cert:
    #!/usr/bin/env bash
    set -euo pipefail
    if security find-identity -p codesigning | grep -q "{{local_identity}}"; then echo "already in keychain"; exit 0; fi
    d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
    printf '[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ext\n[dn]\nCN={{local_identity}}\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > "$d/c.cnf"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/k.pem" -out "$d/c.pem" -days 3650 -config "$d/c.cnf" 2>/dev/null
    # macOS's /usr/bin/openssl is LibreSSL: its pkcs12 already uses the legacy algorithms and has no -legacy flag
    legacy=$(openssl version | grep -q LibreSSL || echo -legacy)
    openssl pkcs12 -export $legacy -inkey "$d/k.pem" -in "$d/c.pem" -out "$d/c.p12" -passout pass:paw
    security import "$d/c.p12" -k ~/Library/Keychains/login.keychain-db -P paw -T /usr/bin/codesign
    echo "created {{local_identity}}; run just dev, then grant Accessibility to paw Dev once"

# Start the release paw at login with launchd instead of the openAtLogin login item
launchd:
    mkdir -p "$(dirname "{{launch_agent}}")"
    cp examples/com.pseudobun.paw.plist "{{launch_agent}}"
    -launchctl bootout gui/$(id -u) "{{launch_agent}}" 2>/dev/null
    @# hand paw to launchd so KeepAlive restarts it after a crash
    @just _quit
    launchctl bootstrap gui/$(id -u) "{{launch_agent}}"
    @echo "loaded {{launch_agent}}"

# Refresh the built-in app icon map from sketchybar's helpers/app_icons.lua
icons path="":
    scripts/gen-app-icons.sh {{path}}

# Render the indicators with your config to a PNG
preview out="build.noindex/preview.png":
    swift build -q
    mkdir -p "$(dirname "{{out}}")"
    .build/debug/paw preview "{{out}}"

# Regenerate examples/config.json5 from the built-in template
examples: build
    .build/debug/paw config template > examples/config.json5

# Follow paw's log
log:
    log stream --level info --predicate 'subsystem BEGINSWITH "com.pseudobun.paw"'

# Re-render Resources/AppIcon.icns from Resources/icon/paw-icon.svg
icon:
    swift scripts/make-icon.swift

# Universal release build zipped into build.noindex/release (CI signs and notarizes it)
release-zip:
    PAW_ARCHS="arm64 x86_64" scripts/bundle.sh build.noindex/release
    cd build.noindex/release && ditto -c -k --sequesterRsrc --keepParent paw.app "paw-$(tr -d '[:space:]' < ../../VERSION)-macos.zip"

# Build and publish a version by hand (normally release-please does this when its PR merges)
release tag=("v" + `tr -d '[:space:]' < VERSION`):
    gh workflow run release.yml -f tag={{tag}}
    @echo "started; gh run watch to follow it"
