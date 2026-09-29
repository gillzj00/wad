#!/usr/bin/env python3
"""Picks the iPhone to install on from `xcrun devicectl list devices --json-output`.

Usage: select_device.py <devicectl json file>

Prints two lines for the chosen phone: its identifier for xcodebuild and
devicectl, and its model. The caller must not print or log the identifier.

Exit status:
  0  a phone that can be reached was found
  2  a phone is paired but cannot be reached (locked, not connected, away)
  3  no paired iPhone at all
  1  the file could not be read

A phone can be reached when its tunnel is "connected" (in use) or
"disconnected" (reachable, what the device list shows as "available").
"unavailable" means paired but not reachable now.
"""
import json
import sys

REACHABLE = ("connected", "disconnected")

UNAVAILABLE_MESSAGE = """\
The iPhone is paired with this Mac but cannot be reached right now.
Unlock the phone and connect it with a USB cable, or put it on the same
Wi-Fi network as this Mac, then run this script again."""

NO_PHONE_MESSAGE = """\
No iPhone is paired with this Mac.
Connect the phone with a USB cable, unlock it and tap Trust, then run this
script again."""


def phones(listing):
    """The physical, paired iPhones of a devicectl listing."""
    found = []
    for device in listing.get("result", {}).get("devices", []):
        hardware = device.get("hardwareProperties", {})
        connection = device.get("connectionProperties", {})
        if hardware.get("reality") != "physical":
            continue
        if hardware.get("deviceType") != "iPhone":
            continue
        if connection.get("pairingState") != "paired":
            continue
        if not hardware.get("udid"):
            continue
        found.append(device)
    return found


def select(listing):
    """Returns (status, device): "ok" with the phone, or "unavailable" / "none" with None."""
    candidates = phones(listing)
    for state in REACHABLE:
        for device in candidates:
            if device.get("connectionProperties", {}).get("tunnelState") == state:
                return "ok", device
    return ("unavailable" if candidates else "none"), None


def main(arguments):
    if len(arguments) != 2:
        print(__doc__, file=sys.stderr)
        return 1
    try:
        with open(arguments[1], encoding="utf-8") as file:
            listing = json.load(file)
    except (OSError, ValueError) as error:
        print(f"could not read the device list: {error}", file=sys.stderr)
        return 1

    status, device = select(listing)
    if status == "unavailable":
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2
    if status == "none":
        print(NO_PHONE_MESSAGE, file=sys.stderr)
        return 3
    hardware = device["hardwareProperties"]
    print(hardware["udid"])
    print(hardware.get("marketingName", "iPhone"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
