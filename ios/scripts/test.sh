#!/usr/bin/env bash
# Builds and tests the Wad scheme on the first available iPhone simulator, so
# the same command works locally and on CI images with different devices.
#
# Usage: ios/scripts/test.sh [--unit | --ui] [extra xcodebuild args]
#   --unit  the unit tests only (WadTests)
#   --ui    the UI tests only (WadUITests)
# Without a flag every test runs. CI runs --unit and --ui as two jobs; the
# same commands work locally.
set -euo pipefail
cd "$(dirname "$0")/.."

only=()
case "${1:-}" in
  --unit)
    shift
    only=(-only-testing:WadTests)
    ;;
  --ui)
    shift
    only=(-only-testing:WadUITests)
    ;;
esac

# The device selection of install-device.sh, against sample device lists.
python3 scripts/test_select_device.py

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
# After the tests xcodebuild may spend up to ten minutes on a sysdiagnose of
# the simulators before it exits; the result bundle has the logs and
# screenshots without it.
xcodebuild test \
  -project Wad.xcodeproj \
  -scheme Wad \
  -destination "id=$device_id" \
  -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO \
  ${only[@]+"${only[@]}"} \
  "$@"
