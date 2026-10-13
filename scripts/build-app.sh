#!/usr/bin/env bash
# Assembles QuickEdit.app from the SwiftPM build.
# Usage: scripts/build-app.sh [release|dev|test]
#   SIGN_IDENTITY="Developer ID Application: …"   # sign with a real identity: hardened runtime + secure timestamp
#                                                 # (default: ad-hoc; scripts/release.sh sets it)
#   VERSION=1.2.3 BUILD=456                       # override ./VERSION and the commit-count build number
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

swift build -c "$CONFIG" --product QuickEdit
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/$NAME.app"
PLIST="$APP/Contents/Info.plist"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/QuickEdit" "$APP/Contents/MacOS/QuickEdit"
cp Resources/Info.plist "$PLIST"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"

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

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements Resources/QuickEdit.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $APP"
