#!/usr/bin/env bash
# Builds and tests the Wad scheme on the first available iPhone simulator, so
# the same command works locally and on CI images with different devices.
# Usage: ios/scripts/test.sh [extra xcodebuild args]
set -euo pipefail
cd "$(dirname "$0")/.."

device_id=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"])
            sys.exit(0)
sys.exit("no available iPhone simulator")
')

echo "Testing on simulator $device_id"
xcodebuild test \
  -project Wad.xcodeproj \
  -scheme Wad \
  -destination "id=$device_id" \
  CODE_SIGNING_ALLOWED=NO \
  "$@"
