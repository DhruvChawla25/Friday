#!/usr/bin/env bash
# Copyright (c) 2026 Dhruv Chawla · SPDX-License-Identifier: MIT
# Builds a Release Friday.app and packages it into build/Friday.dmg.
# The app is ad-hoc signed. Until it is notarized, first launch on another Mac:
# right-click Friday.app → Open (or System Settings → Privacy & Security → Open Anyway).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=build
APP="$BUILD/DerivedData/Build/Products/Release/Friday.app"
STAGE="$BUILD/dmg"
DMG="$BUILD/Friday.dmg"

xcodebuild -project Friday.xcodeproj -scheme Friday -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD/DerivedData" \
  build -quiet

codesign --verify --deep --strict "$APP"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Friday -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
rm -rf "$STAGE"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "✔ $DMG (Friday $VERSION, $(du -h "$DMG" | cut -f1))"
