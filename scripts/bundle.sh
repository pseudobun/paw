#!/usr/bin/env bash
# Builds paw.app from the SwiftPM binary and signs it.
# Usage: scripts/bundle.sh [out_dir]
# PAW_ARCHS="arm64 x86_64" builds a universal binary (default: arm64).
# env: PAW_VERSION (default: from the VERSION file, plus the commit when not on its tag),
#      PAW_BUILD (CFBundleVersion, which Sparkle compares; default: commit count), PAW_BUNDLE_ID, PAW_SIGN_IDENTITY,
#      PAW_TIMESTAMP=1 (secure timestamp, needed for notarization),
#      PAW_DEV=1 (a dev build: "paw Dev", com.pseudobun.paw.dev, no updates; see just dev),
#      PAW_APP_NAME (dev only: the shown name, e.g. "paw Bench" for just bench's own grants)
#      PAW_PROFILE=1 (dev only: timing recorder, debug information and matching dSYM),
#      PAW_DSYM=1 (debug information and dSYM without the timing recorder)
# Signing: PAW_SIGN_IDENTITY if set, else a "Developer ID Application" or "Apple Development"
# identity, else the self-signed "paw Local Signing" certificate (just local-cert), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build.noindex}"
name=paw
bundle_id="${PAW_BUNDLE_ID:-com.pseudobun.paw}"
if [ "${PAW_DEV:-}" = 1 ]; then
  name="${PAW_APP_NAME:-paw Dev}"
  bundle_id="${PAW_BUNDLE_ID:-com.pseudobun.paw.dev}"
  # Dev builds never update themselves.
  PAW_SPARKLE_PUBLIC_KEY="" PAW_FEED_URL="-"
fi
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
# Shown by Finder and Sparkle ("you have …"): the version without build metadata, e.g. 0.1.0-beta.2.
short="${version%%+*}"
build="${PAW_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
# These land in Info.plist: refuse anything that could close a <string> and add keys of its own.
[[ "$version" =~ ^[0-9A-Za-z.+-]+$ ]] || { echo "bad version: $version" >&2; exit 1; }
[[ "$build" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "bad build number: $build" >&2; exit 1; }

# dead_strip + strip -x: about half the size (local symbols aren't needed to run)
arch_flags=""; for a in ${PAW_ARCHS:-arm64}; do arch_flags="$arch_flags --arch $a"; done
profile_flags=""
if [ "${PAW_PROFILE:-}" = 1 ]; then
  [ "${PAW_DEV:-}" = 1 ] || { echo "PAW_PROFILE requires PAW_DEV=1" >&2; exit 1; }
  profile_flags="-Xswiftc -DPAW_PROFILE -Xswiftc -g"
elif [ "${PAW_DSYM:-}" = 1 ]; then
  profile_flags="-Xswiftc -g"
fi
swift build -c release $arch_flags $profile_flags -q -Xlinker -dead_strip
bin_dir="$(swift build -c release $arch_flags $profile_flags -Xlinker -dead_strip --show-bin-path)"
bin="$bin_dir/paw"
# Sparkle (updates): the framework SwiftPM built next to the binary.
# A missing PackageFrameworks makes find fail; pipefail must not end the build before the check below.
sparkle="$( (find "$bin_dir" "$bin_dir/PackageFrameworks" -maxdepth 1 -name Sparkle.framework 2>/dev/null || true) | head -1)"
[ -n "$sparkle" ] || { echo "Sparkle.framework not found in $bin_dir" >&2; exit 1; }
# EdDSA key that signs updates (private half: the SPARKLE_PRIVATE_KEY secret and olympus' keychain).
sparkle_key="${PAW_SPARKLE_PUBLIC_KEY-c9vc9GKhX9zHEAUrLSWfN4soCN0vUAhl68AXWjD06Uc=}"
feed="${PAW_FEED_URL:-https://raw.githubusercontent.com/pseudobun/paw/appcast/appcast.xml}"
[ "$feed" = "-" ] && feed=""
# XML-escaped for the plist below (bundle id, feed and key come from the environment).
xml() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }

app="$out/paw.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin" "$app/Contents/MacOS/paw"
if [ "${PAW_PROFILE:-}" = 1 ] || [ "${PAW_DSYM:-}" = 1 ]; then
  xcrun dsymutil "$bin" -o "$out/paw.dSYM"
  # Compare UUID and architecture, ignoring the different file paths.
  xcrun dwarfdump --uuid "$bin" | awk '{print $2, $3}' > "$out/binary-uuids.txt"
  xcrun dwarfdump --uuid "$out/paw.dSYM" | awk '{print $2, $3}' > "$out/dsym-uuids.txt"
  cmp "$out/binary-uuids.txt" "$out/dsym-uuids.txt" || { echo "dSYM UUID mismatch" >&2; exit 1; }
  [ -s "$out/binary-uuids.txt" ] || { echo "missing binary UUID" >&2; exit 1; }
fi
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
# paw isn't sandboxed, so Sparkle needs no XPC services.
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
strip -x "$app/Contents/MacOS/paw"
cp Resources/AppIcon.icns Resources/menubar.svg "$app/Contents/Resources/"
cp -R Resources/Fonts "$app/Contents/Resources/"
# The Dock helper (optional, Apple silicon, needs SIP's debugging restrictions off; README
# "Faster workspace switching"): `sudo paw dock install` copies these out of the app.
dock="$app/Contents/Resources/dock"
mkdir -p "$dock"
xcrun clang Sources/PawDock/payload.m -shared -fPIC -O2 -fobjc-arc -arch arm64e -mmacosx-version-min=14.0 \
  -framework Foundation -framework CoreGraphics -Wl,-undefined,dynamic_lookup -o "$dock/PawDock.dylib"
xcrun clang Sources/PawDock/loader.m -O2 -fobjc-arc -arch arm64e -mmacosx-version-min=14.0 -framework Foundation \
  -o "$dock/paw-dock-loader"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$(xml "$bundle_id")</string>
  <key>CFBundleName</key><string>$(xml "$name")</string>
  <key>CFBundleDisplayName</key><string>$(xml "$name")</string>
  <key>CFBundleExecutable</key><string>paw</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$(xml "$short")</string>
  <key>CFBundleVersion</key><string>$(xml "$build")</string>
  <key>PawVersion</key><string>$(xml "$version")</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>$(xml "$feed")</string>
  <key>SUPublicEDKey</key><string>$(xml "$sparkle_key")</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>NSHumanReadableCopyright</key><string>© Urban Vidovič</string>
</dict>
</plist>
PLIST

ts="--timestamp=none"; [ "${PAW_TIMESTAMP:-}" = 1 ] && ts="--timestamp"
identity="${PAW_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  # By hash: the same certificate in two keychains makes its name ambiguous to codesign.
  # Developer ID first (its team, and so the Accessibility grant, stays the same), then Apple Development.
  ids="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity="$( { echo "$ids" | grep '"Developer ID Application'; echo "$ids" | grep '"Apple Development'; } | awk 'NR == 1 {print $2}' || true)"
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
  codesign --force $rt $2 -s "$id" "$app/Contents/Resources/dock/PawDock.dylib" &&
    codesign --force $rt $2 -s "$id" "$app/Contents/Resources/dock/paw-dock-loader" &&
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
