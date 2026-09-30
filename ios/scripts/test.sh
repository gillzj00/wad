#!/usr/bin/env bash
# Builds and tests the Wad scheme on the first available iPhone simulator, so
# the same command works locally and on CI images with different devices.
#
# Usage: ios/scripts/test.sh [--unit | --ui] [extra xcodebuild args]
#   --unit  the unit tests only (WadTests)
#   --ui    the UI tests only (WadUITests), spread over simulator clones;
#           WAD_UI_TEST_WORKERS is how many clones (default 3)
# Without a flag every test runs, one at a time. CI runs --unit and --ui as
# two jobs; the same commands work locally.
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
    only=(
      -only-testing:WadUITests
      -parallel-testing-enabled YES
      -parallel-testing-worker-count "${WAD_UI_TEST_WORKERS:-3}"
    )
    ;;
esac

# The device selection of install-device.sh, against sample device lists.
python3 scripts/test_select_device.py

# An iPhone on the newest iOS runtime this Xcode supports: one no newer than
# its simulator SDK (a CI image carries runtimes of later Xcodes too, and the
# clones of a parallel run fail to launch on those). Failing that, the newest.
sdk_version=$(xcodebuild -version -sdk iphonesimulator SDKVersion)
device_id=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
sdk = tuple(int(n) for n in sys.argv[1].split("."))
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    # com.apple.CoreSimulator.SimRuntime.iOS-18-5
    return tuple(int(n) for n in runtime.rsplit("iOS-", 1)[1].split("-"))
runtimes = [
    r for r in devices
    if ".iOS-" in r and any(d["name"].startswith("iPhone") for d in devices[r])
]
if not runtimes:
    sys.exit("no available iPhone simulator")
supported = [r for r in runtimes if version(r) <= sdk] or runtimes
runtime = max(supported, key=version)
print(next(d["udid"] for d in devices[runtime] if d["name"].startswith("iPhone")))
' "$sdk_version")

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
