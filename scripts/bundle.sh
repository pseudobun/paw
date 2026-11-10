#!/usr/bin/env bash
# Builds paw.app from the SwiftPM binary and signs it.
# Usage: scripts/bundle.sh [out_dir]
# PAW_ARCHS="arm64 x86_64" builds a universal binary (default: arm64).
# env: PAW_VERSION (default: from the VERSION file, plus the commit when not on its tag),
#      PAW_BUILD (CFBundleVersion, which Sparkle compares; default: commit count), PAW_BUNDLE_ID, PAW_SIGN_IDENTITY,
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
arch_flags=""; for a in ${PAW_ARCHS:-arm64}; do arch_flags="$arch_flags --arch $a"; done
swift build -c release $arch_flags -q -Xlinker -dead_strip
bin_dir="$(swift build -c release $arch_flags -Xlinker -dead_strip --show-bin-path)"
bin="$bin_dir/paw"
# Sparkle (updates): the framework SwiftPM built next to the binary.
sparkle="$(find "$bin_dir" "$bin_dir/PackageFrameworks" -maxdepth 1 -name Sparkle.framework 2>/dev/null | head -1)"
[ -n "$sparkle" ] || { echo "Sparkle.framework not found in $bin_dir" >&2; exit 1; }
# EdDSA key that signs updates (private half: the SPARKLE_PRIVATE_KEY secret and olympus' keychain).
sparkle_key="${PAW_SPARKLE_PUBLIC_KEY-c9vc9GKhX9zHEAUrLSWfN4soCN0vUAhl68AXWjD06Uc=}"
feed="${PAW_FEED_URL:-https://raw.githubusercontent.com/pseudobun/paw/appcast/appcast.xml}"

app="$out/paw.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin" "$app/Contents/MacOS/paw"
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
# paw isn't sandboxed, so Sparkle needs no XPC services.
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
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
  <key>SUFeedURL</key><string>${feed}</string>
  <key>SUPublicEDKey</key><string>${sparkle_key}</string>
  <key>SUEnableAutomaticChecks</key><true/>
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
# Inside out: Sparkle's helpers, the framework, then the app.
# Hardened runtime (needed for notarization) only with a Developer ID: its library validation
# refuses a framework signed without a Team ID, as self-signed and ad-hoc builds are.
sign() {
  local id="$1" fw="$app/Contents/Frameworks/Sparkle.framework" rt=""
  case "$id" in "Developer ID"*) rt="--options runtime" ;; esac
  codesign --force $rt $2 -s "$id" "$fw/Versions/B/Autoupdate" &&
    codesign --force $rt $2 -s "$id" "$fw/Versions/B/Updater.app" &&
    codesign --force $rt $2 -s "$id" "$fw" &&
    codesign --force $rt $2 -s "$id" "$app"
}
if [ -n "$identity" ] && err="$(sign "$identity" "$ts" 2>&1)"; then
  echo "signed: $identity"
else
  [ -n "$identity" ] && echo "signing with $identity failed ($(echo "$err" | grep -v 'replacing existing' | tail -1)); ad-hoc instead" >&2
  # Release builds must not quietly ship ad-hoc.
  [ -n "${PAW_SIGN_IDENTITY:-}" ] && [ "${PAW_TIMESTAMP:-}" = 1 ] && { echo "release signing failed" >&2; exit 1; }
  sign - "" >/dev/null
  echo "signed: ad-hoc"
fi
codesign --verify --deep --strict "$app"
echo "built: $app ($version)"
