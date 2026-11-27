#!/usr/bin/env bash
# Copyright (c) 2026 Dhruv Chawla · SPDX-License-Identifier: MIT
#
# Builds Release Friday, signs it with "Friday Local Signing" (see
# setup-local-signing.sh) so macOS keeps its permissions across rebuilds,
# installs it as the ONLY copy at /Applications/Friday.app, removes build
# copies from Launch Services (so Spotlight/Launchpad show one Friday), and
# relaunches it in the background without stealing focus.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Friday Local Signing"
KC="$HOME/Library/Keychains/friday-signing.keychain-db"
PASSFILE="$HOME/.config/friday/signing-keychain-password"
APP="build/DerivedData/Build/Products/Release/Friday.app"
DEST="/Applications/Friday.app"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! [ -f "$KC" ] || ! security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "✘ No \"$NAME\" identity. Run Scripts/setup-local-signing.sh once first." >&2
  exit 1
fi

xcodebuild -project Friday.xcodeproj -scheme Friday -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build -quiet

# Re-sign with the stable identity, keeping the app's entitlements and flags.
security unlock-keychain -p "$(cat "$PASSFILE")" "$KC"
codesign --force --sign "$NAME" --keychain "$KC" \
  --preserve-metadata=entitlements,flags,runtime --timestamp=none "$APP"
codesign --verify --strict "$APP"

osascript -e 'quit app "Friday"' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do pgrep -x Friday >/dev/null || break; sleep 1; done

rm -rf "$DEST"
ditto "$APP" "$DEST"

# Only one Friday: unregister every build copy, keep /Applications.
for copy in build/DerivedData/Build/Products/*/Friday.app build/dmg/Friday.app .claude/worktrees/*/build/DerivedData/Build/Products/*/Friday.app; do
  [ -e "$copy" ] && "$LSR" -u "$PWD/$copy" 2>/dev/null || true
done
rm -rf build/DerivedData/Build/Products/*/Friday.app build/dmg
"$LSR" -f "$DEST"

open -g -j "$DEST"
echo "✔ Installed $DEST, signed by \"$NAME\""
codesign -dr - "$DEST" 2>&1 | grep designated
