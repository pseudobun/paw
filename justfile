# paw: build, test and install locally. Signing is picked by scripts/bundle.sh
# (Apple Development identity → "paw Local Signing" → ad-hoc).

app_dir := "/Applications"
cli_link := "/opt/homebrew/bin/paw"
local_identity := "paw Local Signing"
launch_agent := env("HOME") / "Library/LaunchAgents/dev.paw.app.plist"

default: build

# Debug build (.build/debug/paw)
build:
    swift build

# Unit tests (layout tree, commands, key bindings, placement, config, icon map)
test:
    swift test

# Release paw.app into ./build.noindex (.noindex keeps Spotlight from listing a second paw)
bundle:
    scripts/bundle.sh build.noindex

# Release build → /Applications/paw.app, CLI → /opt/homebrew/bin/paw, relaunch
install: bundle
    -paw quit 2>/dev/null; pkill -x paw
    @for i in $(seq 1 30); do pgrep -x paw >/dev/null || break; sleep 0.1; done
    rm -rf "{{app_dir}}/paw.app"
    cp -R build.noindex/paw.app "{{app_dir}}/paw.app"
    ln -sf "{{app_dir}}/paw.app/Contents/MacOS/paw" "{{cli_link}}"
    open "{{app_dir}}/paw.app"
    @echo "installed {{app_dir}}/paw.app, CLI at {{cli_link}}"

uninstall:
    -paw quit 2>/dev/null; pkill -x paw
    -launchctl bootout gui/$(id -u) "{{launch_agent}}" 2>/dev/null
    rm -rf "{{app_dir}}/paw.app" "{{cli_link}}" "{{launch_agent}}"

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
    echo "created {{local_identity}}; run just install, then grant Accessibility once"

# Start paw at login with launchd instead of the openAtLogin login item
launchd: install
    mkdir -p "$(dirname "{{launch_agent}}")"
    sed "s|/Applications|{{app_dir}}|" examples/dev.paw.app.plist > "{{launch_agent}}"
    -launchctl bootout gui/$(id -u) "{{launch_agent}}" 2>/dev/null
    @# install opened paw itself; hand it to launchd so KeepAlive restarts it after a crash
    -pkill -x paw
    @for i in $(seq 1 30); do pgrep -x paw >/dev/null || break; sleep 0.1; done
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
    log stream --level info --predicate 'subsystem == "dev.paw.app"'
