#!/usr/bin/env bash
# Builds the Wad scheme for the first iPhone that can be reached and installs it.
# Needs Config/Local.xcconfig with your DEVELOPMENT_TEAM.
# Usage: ios/scripts/install-device.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/.."

# The device list as JSON: the text output says "unavailable" for a phone that
# is paired and out of reach, which a match on "available" takes for a phone.
devices_json=$(mktemp)
trap 'rm -f "$devices_json"' EXIT
if ! xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1; then
  echo "could not list the devices (xcrun devicectl list devices)" >&2
  exit 1
fi

# Prints what to do and stops here when no phone can be reached.
selection=$(python3 scripts/select_device.py "$devices_json")
device_id=$(printf '%s\n' "$selection" | sed -n 1p)
device_model=$(printf '%s\n' "$selection" | sed -n 2p)

# The identifier is not printed: logs get shared.
echo "Installing on the $device_model"
xcodebuild build \
  -project Wad.xcodeproj \
  -scheme Wad \
  -destination "id=$device_id" \
  -derivedDataPath build/device \
  -allowProvisioningUpdates \
  "$@"
xcrun devicectl device install app --device "$device_id" build/device/Build/Products/Debug-iphoneos/Wad.app
xcrun devicectl device process launch --device "$device_id" com.gillzj00.wad
