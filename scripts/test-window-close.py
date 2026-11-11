#!/usr/bin/env python3
"""Opt-in live close/focus regression; only closes disposable fixture windows."""

import json
import pathlib
import plistlib
import select
import shlex
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
    status = paw("status")
    if "trusted: yes" not in status:
        raise SystemExit("Paw Dev must be running with Accessibility access.")
    if "nativeSpaces: warning:" in status:
        raise SystemExit("Keep one native macOS desktop per display, then run paw-dev recover before testing.")
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
            def launch(role, *args):
                contents = pathlib.Path(temporary) / ("PAW Close " + role + ".app") / "Contents"
                (contents / "MacOS").mkdir(parents=True, exist_ok=True)
                (contents / "Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": "com.pseudobun.paw.close-fixture." + role,
                    "CFBundleName": "PAW Close " + role,
                    "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"}))
                shutil.copy2(binary, contents / "MacOS/fixture")
                process = subprocess.Popen([str(contents / "MacOS/fixture"), *args], stdin=subprocess.PIPE,
                                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                processes.append(process)
                return process

            a, b = launch("A"), launch("B")
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

            def settled_frame(id, owner, name):
                def matches():
                    window = next(w for w in windows() if w["id"] == id)
                    f = window["frame"]
                    actual = list(map(float, fixture_reply(owner, "frame " + name).split()))
                    return f if window["onScreen"] and all(abs(a - f[k]) <= 4 for a, k in zip(actual, ["x", "y", "w", "h"])) else None
                return wait_for(matches)

            def select_placeholder():
                paw("find", "PAW-close-placeholder")
                wait_for(lambda: any(ws["focused"] and any(w["id"] == ids["placeholder"] and w["focused"] for w in ws["windows"])
                                     for ws in query()) and fixture_reply(a, "front") == "com.pseudobun.paw.dev")
                time.sleep(0.5)
                return fixture_reply(a, "pointer")

            def hover(id, owner, native_name):
                f = settled_frame(id, owner, native_name)
                paw("exec", f"{shlex.quote(str(binary))} --move-pointer {f['x'] + f['w'] / 2} {f['y'] + f['h'] / 2}")
                def has_focus():
                    selected = next((w["id"] for ws in query() if ws["focused"] for w in ws["windows"] if w["focused"]), None)
                    return selected == id and fixture_reply(owner, "focused") == native_name
                wait_for(has_focus)

            if json.loads(paw("config", "show"))["focus"]["focusFollowsMouse"]:
                hover(target, b, "target")
                print("PASS: real-window hover before selecting a placeholder")
                for attempt in range(3):
                    select_placeholder()
                    hover(target, b, "target")
                    hover(ids["other"], a, "other")
                    hover(ids["survivor"], a, "survivor")
                    print("PASS: placeholder to real windows", attempt + 1)
            else:
                print("SKIP: hover movement checks (focus-follows-mouse is disabled)")

            def check(name, closing, expected, native_process, native_name, owner=a, quit_app=False):
                placeholder_position = select_placeholder() if native_name is None else None
                focused_name = "other" if name == "background close" else "closing"
                paw("find", "PAW-close-" + focused_name)
                # Let the prior close's focus suppression and resize animation finish.
                time.sleep(0.5)
                hovered = next(w for w in windows() if w["id"] == (target if name == "background close" else expected))
                assert hovered["onScreen"] == (native_name is not None), "Unexpected real-window/placeholder state"
                f = settled_frame(hovered["id"], b if name == "background close" else native_process,
                                  "target" if name == "background close" else native_name) if native_name else None
                selected = ids["other"] if name == "background close" else ids[closing]
                wait_for(lambda: any(ws["focused"] and any(w["id"] == selected and w["focused"] for w in ws["windows"])
                                     for ws in query()))
                assert fixture_reply(owner, "focused") == focused_name, "Close must start with native focus on the intended window"
                events.clear()
                # Warp and close in one app turn so focus-follows-mouse cannot mask close recovery.
                position = placeholder_position or f"{f['x'] + f['w'] / 4} {f['y'] + f['h'] / 4}"
                fixture_reply(owner, ("quit " if quit_app else "close " + closing + " ") + position)
                wait_for(lambda: all(w["id"] != ids[closing] for w in windows()))
                time.sleep(0.6)
                focused = next((w for ws in query() if ws["focused"] for w in ws["windows"] if w["focused"]), None)
                assert focused and focused["id"] == expected, f"{name}: expected {expected}, got {focused and focused['id']}; events {events}; hover point {position}"
                if native_name is None:
                    assert fixture_reply(native_process, "front") == "com.pseudobun.paw.dev", name + ": placeholder left keys with another app"
                else:
                    assert fixture_reply(native_process, "focused") == native_name, name + ": native keyboard focus is wrong"
                assert all(id == expected for id in events), f"{name}: intermediate focus targets {events}"
                print("PASS:", name, "keeps focus on the intended window without intermediate focus targets")

            check("same-app close", "closing", ids["survivor"], a, "survivor")
            check("background close", "survivor", ids["other"], a, "other")
            ids["closing"] = int(fixture_reply(a, "new closing"))
            wait_for(lambda: any(w["id"] == ids["closing"] for w in windows()))
            check("cross-app close with placeholder", "closing", target, b, "target")
            ids["closing"] = int(fixture_reply(a, "new closing"))
            wait_for(lambda: any(w["id"] == ids["closing"] for w in windows()))
            check("hovered placeholder", "closing", ids["placeholder"], a, None)

            decoy = int(fixture_reply(b, "new decoy"))
            for attempt in range(5):
                c = launch("C", "--quit-on-close")
                ids["closing"] = int(fixture_reply(c, "new closing"))
                wait_for(lambda: any(w["id"] == ids["closing"] for w in windows()))
                check(f"process exit {attempt + 1}", "closing", target, b, "target", owner=c, quit_app=attempt % 2 == 0)
                c.wait(timeout=5)

            def close_under_pointer(name, quit_app):
                # Focus follows mouse leaves the pointer inside the window being closed: the
                # window that retiles under it should get focus, not the workspace's first one.
                c = launch("C", "--quit-on-close")
                ids["closing"] = int(fixture_reply(c, "new closing"))
                wait_for(lambda: any(w["id"] == ids["closing"] for w in windows()))
                paw("find", "PAW-close-closing")
                time.sleep(0.5)
                f = settled_frame(ids["closing"], c, "closing")
                wait_for(lambda: fixture_reply(c, "focused") == "closing")
                events.clear()
                # Off-centre: halves are where retiled seams land, and a seam is under no window.
                x, y = f["x"] + f["w"] * 0.37, f["y"] + f["h"] * 0.37
                fixture_reply(c, f"quit {x} {y}" if quit_app else f"close closing {x} {y}")
                c.wait(timeout=5)
                time.sleep(0.6)
                shown = next(ws for ws in query() if ws["focused"])["windows"]
                under = next(w["id"] for w in shown if not w["floating"]
                             and w["frame"]["x"] <= x < w["frame"]["x"] + w["frame"]["w"]
                             and w["frame"]["y"] <= y < w["frame"]["y"] + w["frame"]["h"])
                focused = next((w["id"] for w in shown if w["focused"]), None)
                names = {**{v: k for k, v in ids.items()}, target: "target", decoy: "decoy"}
                assert focused == under, (f"{name}: expected {names[under]} under the pointer, got {names.get(focused)}; "
                                          f"first tile {names[shown[0]['id']]}; events {events}")
                if names[under] == "placeholder":
                    assert fixture_reply(a, "front") == "com.pseudobun.paw.dev", name + ": placeholder left keys with another app"
                else:
                    owner = b if under in (target, decoy) else a
                    assert fixture_reply(owner, "focused") == names[under], name + ": native keyboard focus is wrong"
                assert all(id == under for id in events), f"{name}: intermediate focus targets {events}"
                print("PASS:", name, "focuses the window that retiles under the pointer")

            for attempt in range(4):
                close_under_pointer(f"process exit under pointer {attempt + 1}", quit_app=attempt % 2 == 0)

            # A selected placeholder leaves paw with the keyboard: ⌘W and ⌘Q go to its own app.
            pid = next(line.split()[1] for line in status.splitlines() if line.startswith("pid:"))
            def command_key(code):
                paw("exec", f"{shlex.quote(str(binary))} --command-key {pid} {code}")
            select_placeholder()
            command_key(13)
            wait_for(lambda: all(w["id"] != ids["placeholder"] for w in windows()))
            assert a.poll() is None, "⌘W on a placeholder must close only its window"
            print("PASS: ⌘W on a placeholder closes the window it stands in for")
            for flags in [["--no-close-button"], []]:
                c = launch("C", *flags)
                ids["placeholder"] = int(fixture_reply(c, "new placeholder"))
                wait_for(lambda: any(w["id"] == ids["placeholder"] and not w["onScreen"] for w in windows()))
                select_placeholder()
                if flags:
                    command_key(13)
                    time.sleep(0.5)
                    assert c.poll() is None, "⌘W must not turn a missing close button into Quit for arbitrary apps"
                    assert any(w["id"] == ids["placeholder"] for w in windows())
                    print("PASS: a missing close button does not quit an unrelated app")
                command_key(12)
                c.wait(timeout=5)
                assert a.poll() is None and b.poll() is None, "⌘Q on a placeholder must quit only its app"
                print("PASS: ⌘Q on a placeholder quits its owner", "without a close button" if flags else "with a close button")
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
