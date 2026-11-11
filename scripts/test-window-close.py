#!/usr/bin/env python3
"""Opt-in live close/focus regression; only closes disposable fixture windows."""

import json
import pathlib
import plistlib
import select
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def paw(*args):
    return subprocess.check_output(["paw-dev", *args], text=True)


def query():
    return json.loads(paw("query", "--json"))


def fixture_reply(process, command):
    process.stdin.write(command + "\n")
    process.stdin.flush()
    if not select.select([process.stdout], [], [], 5)[0]:
        raise AssertionError("Fixture did not reply to " + command)
    return process.stdout.readline().strip()


def wait_for(predicate):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for fixture windows")


def main():
    if "trusted: yes" not in paw("status"):
        raise SystemExit("Paw Dev must be running with Accessibility access.")
    workspaces = query()
    original = next(ws["name"] for ws in workspaces if ws["focused"])
    empty = next((ws for ws in workspaces if not ws["visible"] and not ws["windows"]), None)
    if empty is None:
        raise SystemExit("An empty, hidden workspace is required; no user windows were moved.")
    processes = []
    subscriber = None
    with tempfile.TemporaryDirectory(prefix="paw-close-") as temporary:
        try:
            binary = pathlib.Path(temporary) / "fixture"
            subprocess.run(["swiftc", str(ROOT / "Tests/Fixtures/WindowClose.swift"), "-o", str(binary)], check=True)
            paw("workspace", empty["name"])
            paw("layout", "bsp")
            for role in ["A", "B"]:
                contents = pathlib.Path(temporary) / ("PAW Close " + role + ".app") / "Contents"
                (contents / "MacOS").mkdir(parents=True)
                (contents / "Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": "com.pseudobun.paw.close-fixture." + role,
                    "CFBundleName": "PAW Close " + role,
                    "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"}))
                shutil.copy2(binary, contents / "MacOS/fixture")
                processes.append(subprocess.Popen([str(contents / "MacOS/fixture")], stdin=subprocess.PIPE,
                                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True))
            a, b = processes
            ids = {name: int(fixture_reply(a, "new " + name))
                   for name in ["placeholder", "survivor", "other", "closing"]}
            target = int(fixture_reply(b, "new target"))

            def windows():
                return [w for ws in query() for w in ws["windows"]]

            wait_for(lambda: set(ids.values()) | {target} <= {w["id"] for w in windows()})
            wait_for(lambda: any(w["id"] == ids["placeholder"] and not w["onScreen"] for w in windows()))
            subscriber = subprocess.Popen(["paw-dev", "subscribe", "windowFocused"], stdout=subprocess.PIPE, text=True)
            ready = threading.Event()
            events = []

            def collect():
                for line in subscriber.stdout:
                    event = json.loads(line)
                    if event["event"] == "snapshot":
                        ready.set()
                    elif event["event"] == "windowFocused":
                        events.append(event["data"]["window"])

            reader = threading.Thread(target=collect, daemon=True)
            reader.start()
            assert ready.wait(5), "Focus event subscription did not start"

            def check(name, closing, expected, native_process, native_name):
                paw("find", "PAW-close-" + ("other" if name == "background close" else "closing"))
                # Let the prior close's focus suppression and resize animation finish.
                time.sleep(0.5)
                hovered = next(w for w in windows() if w["id"] == (target if name == "background close" else expected))
                assert hovered["onScreen"], "The hover target must be a real visible window"
                f = hovered["frame"]
                fixture_reply(a, f"hover {f['x'] + f['w'] / 4} {f['y'] + f['h'] / 4}")
                time.sleep(0.1)
                events.clear()
                fixture_reply(a, "close " + closing)
                wait_for(lambda: all(w["id"] != ids[closing] for w in windows()))
                time.sleep(0.6)
                focused = next((w for ws in query() if ws["focused"] for w in ws["windows"] if w["focused"]), None)
                assert focused and focused["id"] == expected, f"{name}: expected {expected}, got {focused and focused['id']}"
                assert fixture_reply(native_process, "focused") == native_name, name + ": native keyboard focus is wrong"
                assert all(id == expected for id in events), f"{name}: intermediate focus targets {events}"
                print("PASS:", name, "keeps focus on the intended window without intermediate focus targets")

            check("same-app close", "closing", ids["survivor"], a, "survivor")
            check("background close", "survivor", ids["other"], a, "other")
            ids["closing"] = int(fixture_reply(a, "new closing"))
            wait_for(lambda: any(w["id"] == ids["closing"] for w in windows()))
            check("cross-app close with placeholder", "closing", target, b, "target")
        finally:
            if subscriber is not None:
                subscriber.terminate()
                subscriber.wait(timeout=5)
            for process in processes:
                process.terminate()
                process.wait(timeout=5)
            paw("workspace", empty["name"])
            paw("layout", empty["layout"])
            paw("workspace", original)


if __name__ == "__main__":
    main()
