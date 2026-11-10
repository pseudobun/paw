#!/usr/bin/env bash
# Builds paw.app from the SwiftPM binary and signs it.
# Usage: scripts/bundle.sh [out_dir]   (env: PAW_BUNDLE_ID, PAW_SIGN_IDENTITY)
# Signing: PAW_SIGN_IDENTITY if set, else an "Apple Development" identity, else the
# self-signed "paw Local Signing" certificate (just local-cert), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build.noindex}"
bundle_id="${PAW_BUNDLE_ID:-dev.paw.app}"
version="$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo dev)"
short="$(echo "$version" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+' || echo 0.1.0)"

# dead_strip + strip -x: about half the size (local symbols aren't needed to run)
swift build -c release --arch arm64 -q -Xlinker -dead_strip
bin="$(swift build -c release --arch arm64 -Xlinker -dead_strip --show-bin-path)/paw"

app="$out/paw.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/paw"
strip -x "$app/Contents/MacOS/paw"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${bundle_id}</string>
  <key>CFBundleName</key><string>paw</string>
  <key>CFBundleDisplayName</key><string>paw</string>
  <key>CFBundleExecutable</key><string>paw</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${short}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© Urban Vidovič</string>
</dict>
</plist>
PLIST

identity="${PAW_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"' || true)"
fi
if [ -z "$identity" ] && security find-identity -p codesigning 2>/dev/null | grep -q "paw Local Signing"; then
  identity="paw Local Signing"
fi
# A locked keychain (e.g. over SSH) makes codesign fail with errSecInternalComponent:
# fall back to ad-hoc instead of leaving a broken signature.
if [ -n "$identity" ] && err="$(codesign --force --options runtime --timestamp=none -s "$identity" "$app" 2>&1)"; then
  echo "signed: $identity"
else
  [ -n "$identity" ] && echo "signing with $identity failed ($(echo "$err" | grep -v 'replacing existing' | tail -1)); ad-hoc instead" >&2
  codesign --force -s - "$app"
  echo "signed: ad-hoc"
fi
codesign -v "$app"
echo "built: $app ($version)"
