#!/usr/bin/env bash
# Builds the Wad scheme for the first connected iPhone and installs it.
# Needs Config/Local.xcconfig with your DEVELOPMENT_TEAM.
# Usage: ios/scripts/install-device.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/.."

device_id=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && /connected|available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')
if [ -z "$device_id" ]; then
  echo "no connected iPhone" >&2
  exit 1
fi

echo "Installing on device $device_id"
xcodebuild build \
  -project Wad.xcodeproj \
  -scheme Wad \
  -destination "id=$device_id" \
  -derivedDataPath build/device \
  -allowProvisioningUpdates \
  "$@"
xcrun devicectl device install app --device "$device_id" build/device/Build/Products/Debug-iphoneos/Wad.app
xcrun devicectl device process launch --device "$device_id" com.gillzj00.wad
