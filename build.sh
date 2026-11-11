#!/usr/bin/env bash
#
# Build Chapterize.app without opening Xcode.
#
#   ./build.sh            build build/Chapterize.app
#   ./build.sh --run      build, then launch it
#   ./build.sh --install  build, then copy it to /Applications
#
# Needs Xcode 26+ (or its Command Line Tools) for the macOS 26 SDK / FoundationModels.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Chapterize"
APP="build/${APP_NAME}.app"

echo "==> Compiling (release)…"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so Gatekeeper / Launch Services are happy running it locally.
codesign --force --sign - --timestamp=none "$APP" >/dev/null

# Make Finder / the Dock pick up the .srt document type and new icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

echo "==> Built $APP"

case "${1:-}" in
  --run)
    open "$APP"
    ;;
  --install)
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/${APP_NAME}.app" || true
    echo "==> Installed to /Applications/${APP_NAME}.app"
    ;;
esac
