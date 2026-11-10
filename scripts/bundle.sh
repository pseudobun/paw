#!/usr/bin/env bash
# Builds paw.app from the SwiftPM binary and signs it.
# Usage: scripts/bundle.sh [out_dir]
# PAW_ARCHS="arm64 x86_64" builds a universal binary (default: arm64).
# env: PAW_VERSION (default: from the VERSION file, plus the commit when not on its tag),
#      PAW_BUILD (CFBundleVersion, default: commit count), PAW_BUNDLE_ID, PAW_SIGN_IDENTITY,
#      PAW_TIMESTAMP=1 (secure timestamp, needed for notarization)
# Signing: PAW_SIGN_IDENTITY if set, else a "Developer ID Application" or "Apple Development"
# identity, else the self-signed "paw Local Signing" certificate (just local-cert), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build.noindex}"
bundle_id="${PAW_BUNDLE_ID:-com.pseudobun.paw}"
base="$(tr -d '[:space:]' < VERSION)"
if [ -z "${PAW_VERSION:-}" ]; then
  commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  if [ "$(git describe --tags --exact-match 2>/dev/null)" = "v$base" ] && git diff --quiet HEAD 2>/dev/null; then
    PAW_VERSION="$base"
  else
    PAW_VERSION="$base+$commit$(git diff --quiet HEAD 2>/dev/null || echo .dirty)"
  fi
fi
version="$PAW_VERSION"
# CFBundleShortVersionString must be plain x.y.z; the full version goes in PawVersion.
short="$(echo "$version" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+' || echo 0.0.0)"
build="${PAW_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# dead_strip + strip -x: about half the size (local symbols aren't needed to run)
arch_flags=(); for a in ${PAW_ARCHS:-arm64}; do arch_flags+=(--arch "$a"); done
swift build -c release "${arch_flags[@]}" -q -Xlinker -dead_strip
bin="$(swift build -c release "${arch_flags[@]}" -Xlinker -dead_strip --show-bin-path)/paw"

app="$out/paw.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/paw"
strip -x "$app/Contents/MacOS/paw"
cp Resources/AppIcon.icns Resources/menubar.svg "$app/Contents/Resources/"
cp -R Resources/Fonts "$app/Contents/Resources/"
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
  <key>CFBundleVersion</key><string>${build}</string>
  <key>PawVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© Urban Vidovič</string>
</dict>
</plist>
PLIST

ts="--timestamp=none"; [ "${PAW_TIMESTAMP:-}" = 1 ] && ts="--timestamp"
identity="${PAW_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(Developer ID Application|Apple Development)[^"]*"' | head -1 | tr -d '"' || true)"
fi
if [ -z "$identity" ] && security find-identity -p codesigning 2>/dev/null | grep -q "paw Local Signing"; then
  identity="paw Local Signing"
fi
# A locked keychain (e.g. over SSH) makes codesign fail with errSecInternalComponent:
# fall back to ad-hoc instead of leaving a broken signature.
if [ -n "$identity" ] && err="$(codesign --force --options runtime "$ts" -s "$identity" "$app" 2>&1)"; then
  echo "signed: $identity"
else
  [ -n "$identity" ] && echo "signing with $identity failed ($(echo "$err" | grep -v 'replacing existing' | tail -1)); ad-hoc instead" >&2
  # Release builds must not quietly ship ad-hoc.
  [ -n "${PAW_SIGN_IDENTITY:-}" ] && [ "${PAW_TIMESTAMP:-}" = 1 ] && { echo "release signing failed" >&2; exit 1; }
  codesign --force -s - "$app"
  echo "signed: ad-hoc"
fi
codesign -v "$app"
echo "built: $app ($version)"
