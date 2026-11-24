#!/usr/bin/env bash
# Regenerates the app icon from the ribbon renderer in Friday/Design.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -O -o build/icongen \
  Friday/Design/RibbonModel.swift Friday/Design/RibbonView.swift Scripts/IconGen/main.swift
mkdir -p Friday/Assets.xcassets
[ -f Friday/Assets.xcassets/Contents.json ] || echo '{"info":{"author":"xcode","version":1}}' > Friday/Assets.xcassets/Contents.json
build/icongen Friday/Assets.xcassets/AppIcon.appiconset
