#!/usr/bin/env bash
# Assembles QuickEdit.app from the SwiftPM build.
# Usage: scripts/build-app.sh [release|dev|test]
#   SIGN_IDENTITY="Developer ID Application: …"   # sign with a real identity: hardened runtime + secure timestamp
#                                                 # (default: ad-hoc; scripts/release.sh sets it)
#   ARCH=arm64                                    # build for one architecture (default: this Mac's)
#   VERSION=1.2.3 BUILD=456                      # override ./VERSION and the commit-count build number
set -euo pipefail
cd "$(dirname "$0")/.."

# The version lives in ./VERSION; the build number counts commits, so it only ever grows.
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

VARIANT="${1:-release}"
case "$VARIANT" in
  release) CONFIG=release; NAME="QuickEdit";      BUNDLE_ID="com.itsjavi.quickedit";      SCHEME="quickedit" ;;
  dev)     CONFIG=debug;   NAME="QuickEdit Dev";  BUNDLE_ID="com.itsjavi.quickedit.dev";  SCHEME="quickedit-dev" ;;
  test)    CONFIG=debug;   NAME="QuickEdit Test"; BUNDLE_ID="com.itsjavi.quickedit.test"; SCHEME="quickedit-test" ;;
  *) echo "unknown variant: $VARIANT" >&2; exit 64 ;;
esac
# The Quick Look extensions register system-wide providers: only the release build embeds them, unless QUICKLOOK=1.
if [[ -z "${QUICKLOOK:-}" ]]; then QUICKLOOK=$([[ "$VARIANT" == "release" ]] && echo 1 || echo 0); fi
# product:Info.plist in Resources/QuickLook:bundle id suffix
QL_EXTENSIONS=(QuickEditQuickLook:Info.plist:quicklook QuickEditThumbnail:Thumbnail-Info.plist:thumbnail)

# OPTIMIZE=1 optimizes a debug (Dev/Test) build, keeping its DEBUG hooks, for performance measurements.
SWIFT_FLAGS=(-c "$CONFIG" --disable-keychain)  # never a Keychain prompt when packages download
if [[ -n "${ARCH:-}" ]]; then SWIFT_FLAGS+=(--arch "$ARCH"); fi
if [[ -n "${OPTIMIZE:-}" && "$CONFIG" == "debug" ]]; then
  SWIFT_FLAGS+=(-Xswiftc -O -Xcc -O2 --scratch-path .build/optimized-debug)
fi
swift build "${SWIFT_FLAGS[@]}" --product QuickEdit
if [[ "$QUICKLOOK" == "1" ]]; then
  for ext in "${QL_EXTENSIONS[@]}"; do swift build "${SWIFT_FLAGS[@]}" --product "${ext%%:*}"; done
fi
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
APP="build/$NAME.app"
PLIST="$APP/Contents/Info.plist"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
# SwiftPM also adds this checkout's build folder as an rpath; the bundle only needs @-relative ones.
strip_build_rpaths() {
  otool -l "$1" | awk '/LC_RPATH/ { getline; getline; print $2 }' | { grep '^/' || true; } |
    while read -r path; do install_name_tool -delete_rpath "$path" "$1" 2>/dev/null; done
}
# Sparkle (updates); ditto keeps the framework's symlinks.
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Sparkle ships universal; a one-architecture build keeps only that slice (signed again below).
if [[ -n "${ARCH:-}" ]]; then
  find "$APP/Contents/Frameworks/Sparkle.framework" -type f -perm -u+x | while read -r binary; do
    archs="$(lipo -archs "$binary" 2>/dev/null || true)"
    if [[ " $archs " == *" $ARCH "* && "$archs" != "$ARCH" ]]; then lipo -thin "$ARCH" "$binary" -output "$binary"; fi
  done
fi
cp "$BIN/QuickEdit" "$APP/Contents/MacOS/QuickEdit"
strip_build_rpaths "$APP/Contents/MacOS/QuickEdit"
cp Resources/Info.plist "$PLIST"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
# File and folder icons for the sidebar and Quick Open (scripts/vendor-material-icons.sh).
rsync -a --delete --exclude subset.json Resources/MaterialIcons/ "$APP/Contents/Resources/MaterialIcons/"

pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
pb "Set :CFBundleIdentifier $BUNDLE_ID"
pb "Set :CFBundleName $NAME"
pb "Set :CFBundleDisplayName $NAME"
pb "Set :AppVariant $VARIANT"
pb "Set :AppURLScheme $SCHEME"
pb "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_ID"
pb "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $SCHEME"
pb "Set :CFBundleShortVersionString $VERSION"
pb "Set :CFBundleVersion $BUILD"
# Updates (Sparkle, decision-7): the feed URL is in Info.plist; the public EdDSA key comes from
# Resources/SparklePublicKey.txt. Dev and Test builds have no updater, so they never replace themselves.
if [[ "$VARIANT" == "release" ]]; then
  # No key file yet is a warning, not a failure (set -e would stop at a failed read).
  SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$({ tr -d '[:space:]' < Resources/SparklePublicKey.txt; } 2>/dev/null || true)}"
  if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    pb "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY"
  else
    echo "⚠ No Resources/SparklePublicKey.txt: this build can't update itself" >&2
  fi
else
  pb "Delete :SUFeedURL"
fi
if [[ "$VARIANT" == "test" ]]; then
  # Background agent build: no Dock icon, never steals focus, no App Nap.
  pb "Add :LSUIElement bool true"
  pb "Add :NSAppSleepDisabled bool true"
  pb "Add :AppBackground bool true"
fi

# App icon (Icon Composer .icon -> Assets.car + AppIcon.icns).
if [[ -d Resources/AppIcon.icon ]]; then
  ICON_DIR="$(mktemp -d)"
  # Absolute paths: actool can resolve relative ones against another project's directory.
  xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" --app-icon AppIcon \
    --platform macosx --target-device mac --minimum-deployment-target 26.0 \
    --output-partial-info-plist "$ICON_DIR/icon.plist" --errors --warnings >/dev/null
  /usr/libexec/PlistBuddy -c "Merge $ICON_DIR/icon.plist" "$PLIST"
  rm -rf "$ICON_DIR"
fi

# Quick Look extensions (decision-5), signed before the app that seals them.
if [[ "$QUICKLOOK" == "1" ]]; then
  for ext in "${QL_EXTENSIONS[@]}"; do
    IFS=: read -r PRODUCT INFO SUFFIX <<< "$ext"
    APPEX="$APP/Contents/PlugIns/$PRODUCT.appex"
    mkdir -p "$APPEX/Contents/MacOS"
    cp "$BIN/$PRODUCT" "$APPEX/Contents/MacOS/$PRODUCT"
    strip_build_rpaths "$APPEX/Contents/MacOS/$PRODUCT"
    cp "Resources/QuickLook/$INFO" "$APPEX/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.$SUFFIX" "$APPEX/Contents/Info.plist"
    for key in CFBundleShortVersionString CFBundleVersion; do
      /usr/libexec/PlistBuddy -c "Set :$key $(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")" "$APPEX/Contents/Info.plist"
    done
  done
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
# codesign without its "replacing existing signature" note (Sparkle's parts come pre-signed).
sign() { codesign "$@" 2> >(grep -v ': replacing existing signature$' >&2); }
# Nested code is signed before the bundle that contains it, innermost first (Sparkle's order; the Downloader
# service keeps its own entitlements).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "${SIGN_FLAGS[@]}" "$SPARKLE/XPCServices/Installer.xpc"
sign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "${SIGN_FLAGS[@]}" "$SPARKLE/Autoupdate"
sign "${SIGN_FLAGS[@]}" "$SPARKLE/Updater.app"
sign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$QUICKLOOK" == "1" ]]; then
  # Both extensions share the sandbox entitlements.
  QL_ENTITLEMENTS=Resources/QuickLook/QuickEditQuickLook.entitlements
  for APPEX in "$APP"/Contents/PlugIns/*.appex; do
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
      codesign --force --sign - --entitlements "$QL_ENTITLEMENTS" "$APPEX"
    else
      codesign --force --options runtime --timestamp --entitlements "$QL_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APPEX"
    fi
  done
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements Resources/QuickEdit.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $APP"
