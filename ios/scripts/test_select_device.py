#!/usr/bin/env python3
"""Tests of select_device.py against device lists shaped like the output of
`xcrun devicectl list devices --json-output`. The identifiers are made up.

Run: python3 ios/scripts/test_select_device.py
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import select_device  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "select_device.py")

PHONE = "00000000-0000000000000001"
OTHER_PHONE = "00000000-0000000000000002"
SIMULATOR = "AAAAAAAA-0000-0000-0000-000000000001"


def device(udid, tunnel, *, kind="iPhone", reality="physical", pairing="paired", model="iPhone 17 Pro Max"):
    connection = {"pairingState": pairing, "tunnelState": tunnel}
    if tunnel != "unavailable":
        connection["transportType"] = "wired"
    return {
        "connectionProperties": connection,
        "deviceProperties": {"name": "Test phone"},
        "hardwareProperties": {
            "deviceType": kind,
            "marketingName": model,
            "platform": "iOS",
            "reality": reality,
            "udid": udid,
        },
        "identifier": "BBBBBBBB-0000-0000-0000-000000000001",
    }


def listing(*devices):
    return {"info": {"outcome": "success"}, "result": {"devices": list(devices)}}


def simulator(tunnel="connected"):
    return device(SIMULATOR, tunnel, reality="simulated", model="iPhone 17 Pro")


class SelectTests(unittest.TestCase):
    def chosen(self, *devices):
        status, found = select_device.select(listing(*devices))
        return status, found and found["hardwareProperties"]["udid"]

    def test_a_connected_phone_is_chosen(self):
        self.assertEqual(self.chosen(device(PHONE, "connected")), ("ok", PHONE))

    def test_an_available_phone_is_chosen(self):
        self.assertEqual(self.chosen(device(PHONE, "disconnected")), ("ok", PHONE))

    def test_an_unavailable_phone_is_not_chosen(self):
        self.assertEqual(self.chosen(device(PHONE, "unavailable")), ("unavailable", None))

    def test_an_unavailable_phone_is_not_chosen_next_to_a_running_simulator(self):
        # What the old text match got wrong: "unavailable" contains "available",
        # and a booted simulator is "connected".
        self.assertEqual(
            self.chosen(simulator("connected"), device(PHONE, "unavailable"), simulator("disconnected")),
            ("unavailable", None),
        )

    def test_a_reachable_phone_wins_over_an_unavailable_one(self):
        self.assertEqual(
            self.chosen(device(OTHER_PHONE, "unavailable"), device(PHONE, "disconnected")),
            ("ok", PHONE),
        )

    def test_a_connected_phone_wins_over_an_available_one(self):
        self.assertEqual(
            self.chosen(device(OTHER_PHONE, "disconnected"), device(PHONE, "connected")),
            ("ok", PHONE),
        )

    def test_simulators_ipads_and_watches_are_not_phones(self):
        self.assertEqual(
            self.chosen(
                simulator(),
                device(OTHER_PHONE, "connected", kind="iPad", model="iPad Pro"),
                device(OTHER_PHONE, "connected", kind="appleWatch", model="Apple Watch"),
            ),
            ("none", None),
        )

    def test_a_phone_that_is_not_paired_is_not_chosen(self):
        self.assertEqual(self.chosen(device(PHONE, "connected", pairing="unpaired")), ("none", None))

    def test_an_unknown_state_is_not_reachable(self):
        self.assertEqual(self.chosen(device(PHONE, "somethingNew")), ("unavailable", None))

    def test_an_empty_list(self):
        self.assertEqual(self.chosen(), ("none", None))
        self.assertEqual(select_device.select({}), ("none", None))


class CommandTests(unittest.TestCase):
    def run_script(self, content):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as file:
            file.write(content)
        try:
            return subprocess.run([sys.executable, SCRIPT, file.name], capture_output=True, text=True, check=False)
        finally:
            os.unlink(file.name)

    def test_prints_the_identifier_and_the_model(self):
        result = self.run_script(json.dumps(listing(simulator(), device(PHONE, "connected"))))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), [PHONE, "iPhone 17 Pro Max"])
        self.assertEqual(result.stderr, "")

    def test_tells_what_to_do_when_the_phone_is_unavailable(self):
        result = self.run_script(json.dumps(listing(simulator(), device(PHONE, "unavailable"))))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("paired with this Mac but cannot be reached", result.stderr)
        self.assertIn("Unlock the phone", result.stderr)
        self.assertIn("USB", result.stderr)
        self.assertIn("same\nWi-Fi", result.stderr)
        self.assertNotIn(PHONE, result.stderr)

    def test_tells_when_there_is_no_phone(self):
        result = self.run_script(json.dumps(listing(simulator())))
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("No iPhone is paired", result.stderr)

    def test_fails_on_a_file_that_is_not_json(self):
        result = self.run_script("Name   Hostname   Identifier   State\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
