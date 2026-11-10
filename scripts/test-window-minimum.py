#!/usr/bin/env python3
"""Opt-in live AX regression: uses an empty workspace and restores the previous one."""

import json
import pathlib
import plistlib
import select
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def paw(*args):
    return subprocess.check_output(["paw", *args], text=True)


def query():
    return json.loads(paw("query", "--json"))


def fixture_reply(process, command):
    process.stdin.write(command + "\n")
    process.stdin.flush()
    if not select.select([process.stdout], [], [], 8)[0]:
        raise AssertionError("Fixture did not reply to " + command)
    return process.stdout.readline().strip()


def main():
    workspaces = query()
    original = next(ws["name"] for ws in workspaces if ws["focused"])
    empty = next((ws["name"] for ws in workspaces if not ws["visible"] and not ws["windows"]), None)
    if empty is None:
        raise SystemExit("An empty, hidden workspace is required; no user windows were moved.")
    layout = next(ws["layout"] for ws in workspaces if ws["name"] == empty)
    with tempfile.TemporaryDirectory(prefix="paw-minimum-") as temporary:
        app = pathlib.Path(temporary) / "PAW Minimum Fixture.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.pseudobun.paw.minimum-fixture",
            "CFBundleName": "PAW Minimum Fixture",
            "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"}))
        binary = contents / "MacOS/fixture"
        subprocess.run(["swiftc", str(ROOT / "Tests/Fixtures/WindowMinimum.swift"),
                        "-o", str(binary)], check=True)
        process = None
        try:
            paw("workspace", empty)
            paw("layout", "bsp")
            process = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, text=True)
            deadline = time.monotonic() + 12
            hidden = False
            while time.monotonic() < deadline:
                windows = [w for ws in query() for w in ws["windows"] if w["title"] == "PAW minimum regression"]
                if windows and not windows[0]["onScreen"]:
                    width = windows[0]["frame"]["w"]
                    if not 400 <= width < 1000:
                        raise AssertionError("Fixture needs a 400–999 point tile; disable canvas zoom for this test.")
                    hidden = True
                    break
                time.sleep(0.1)
            if not hidden:
                raise AssertionError("Fixture did not become a placeholder; use a display narrower than 2000 points.")
            paw("find", "PAW minimum regression")
            time.sleep(0.4)
            window = next(w for ws in query() for w in ws["windows"] if w["title"] == "PAW minimum regression")
            assert not window["onScreen"], "A real minimum must remain a placeholder"
            reply = fixture_reply(process, "lower-minimum")
            assert reply == "minimum-lowered"
            # A pending check must not reveal a window after leaving its workspace.
            paw("find", "PAW minimum regression")
            paw("workspace", original)
            time.sleep(0.3)
            window = next(w for ws in query() for w in ws["windows"] if w["title"] == "PAW minimum regression")
            assert not window["onScreen"], "Pending check revealed a hidden workspace"
            parked = fixture_reply(process, "parked")
            assert parked == "parked", "Hidden window bounds: " + parked
            paw("workspace", empty)
            # Switching back must recover native focus without a corrective `find`.
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                window = next(w for ws in query() for w in ws["windows"] if w["title"] == "PAW minimum regression")
                if (window["onScreen"] and fixture_reply(process, "focused") == "focused"
                        and fixture_reply(process, "parked") == "not-parked"):
                    print("PASS: workspace switch recovered the window and its native keyboard focus")
                    return
                time.sleep(0.1)
            if not window["onScreen"]:
                raise AssertionError("Window stayed hidden after switching back to its workspace")
            raise AssertionError("Recovery did not restore both visible bounds and native keyboard focus")
        finally:
            if process is not None:
                process.terminate()
                process.wait(timeout=5)
            paw("workspace", empty)
            paw("layout", layout)
            paw("workspace", original)


if __name__ == "__main__":
    main()
