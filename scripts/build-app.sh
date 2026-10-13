#!/usr/bin/env bash
# Assembles QuickEdit.app from the SwiftPM build.
# Usage: scripts/build-app.sh [release|dev|test]
set -euo pipefail
cd "$(dirname "$0")/.."

VARIANT="${1:-release}"
case "$VARIANT" in
  release) CONFIG=release; NAME="QuickEdit";      BUNDLE_ID="com.itsjavi.quickedit";      SCHEME="quickedit" ;;
  dev)     CONFIG=debug;   NAME="QuickEdit Dev";  BUNDLE_ID="com.itsjavi.quickedit.dev";  SCHEME="quickedit-dev" ;;
  test)    CONFIG=debug;   NAME="QuickEdit Test"; BUNDLE_ID="com.itsjavi.quickedit.test"; SCHEME="quickedit-test" ;;
  *) echo "unknown variant: $VARIANT" >&2; exit 64 ;;
esac
# The Quick Look extension registers a system-wide preview provider: only the release build embeds it, unless QUICKLOOK=1.
if [[ -z "${QUICKLOOK:-}" ]]; then QUICKLOOK=$([[ "$VARIANT" == "release" ]] && echo 1 || echo 0); fi

swift build -c "$CONFIG" --product QuickEdit
if [[ "$QUICKLOOK" == "1" ]]; then swift build -c "$CONFIG" --product QuickEditQuickLook; fi
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
if [[ -n "${BUILD_NUMBER:-}" ]]; then pb "Set :CFBundleVersion $BUILD_NUMBER"; fi
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

# Quick Look extension (decision-5), signed before the app that seals it.
APPEX="$APP/Contents/PlugIns/QuickEditQuickLook.appex"
if [[ "$QUICKLOOK" == "1" ]]; then
  mkdir -p "$APPEX/Contents/MacOS"
  cp "$BIN/QuickEditQuickLook" "$APPEX/Contents/MacOS/QuickEditQuickLook"
  cp Resources/QuickLook/Info.plist "$APPEX/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.quicklook" "$APPEX/Contents/Info.plist"
  for key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Set :$key $(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")" "$APPEX/Contents/Info.plist"
  done
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$QUICKLOOK" == "1" ]]; then
  QL_ENTITLEMENTS=Resources/QuickLook/QuickEditQuickLook.entitlements
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --entitlements "$QL_ENTITLEMENTS" "$APPEX"
  else
    codesign --force --options runtime --timestamp --entitlements "$QL_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APPEX"
  fi
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements Resources/QuickEdit.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $APP"
