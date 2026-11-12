#!/usr/bin/env python3
"""One controller for just bench. Importing this module launches nothing."""


import argparse
import ctypes
import datetime as dt
import getpass
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import pwd
import re
import select
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
from contextlib import ExitStack

ROOT = Path(__file__).resolve().parents[2]
DEV_ID = "com.pseudobun.paw.dev"  # quick diagnostics drive the developer's running paw Dev
# Controlled runs use their own app, data, socket, defaults and privacy grants, never the daily PAW's.
BENCH_ID = "com.pseudobun.paw.bench.dev"
FIXTURE_NAME = "PAW Performance Fixture"
SCENES = ("switch", "ops", "idle", "overview-off", "overview-on")
SOURCE_PATHS = ("Sources", "Resources", "Package.swift", "Package.resolved", "VERSION",
                "scripts/bundle.sh", "scripts/bench", "Tests/Fixtures/Performance.swift")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def error_chain(error):
    messages, seen = [], set()
    while error is not None and id(error) not in seen:
        seen.add(id(error)); messages.append(str(error) or type(error).__name__)
        error = error.__cause__ or error.__context__
    return list(reversed(messages))


def command(*args, check=True, **kwargs):
    result = subprocess.run([str(a) for a in args], text=True, capture_output=True, **kwargs)
    require(not check or result.returncode == 0,
            f"{' '.join(map(str, args))}: {result.stderr or result.stdout}")
    return result.stdout.strip()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def load(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def label(value):
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", value), "invalid build label")
    return value


def environment():
    power = command("pmset", "-g", "batt")
    source = re.search(r"Now drawing from '([^']+)'", power)
    require(source is not None, "cannot determine power source")
    return {"machine": command("sysctl", "-n", "hw.model"),
            "architecture": command("uname", "-m"), "os": command("sw_vers"),
            "xcode": command("xcodebuild", "-version"), "swift": command("swift", "--version"),
            "power": power, "power_source": source.group(1),
            "power_settings": command("pmset", "-g", "custom")}


def archive_untracked_sources(path):
    with tarfile.open(path, "w") as archive:
        paths = command("git", "ls-files", "-z", "--others", "--exclude-standard", "--", *SOURCE_PATHS, cwd=ROOT).split("\0")
        for name in paths:
            source = ROOT / name
            if name and source.is_file():
                require(source.resolve().is_relative_to(ROOT.resolve()), "untracked source points outside the checkout")
                archive.add(source, arcname=name, recursive=False)


def build(args):
    out = args.builds.resolve() / label(args.label)
    require((Path.home() / "Library/Keychains/paw-bench.keychain-db").exists(), "run just bench-cert once: benchmark builds need a stable signature")
    os.umask(0o077)
    out.mkdir(parents=True, exist_ok=False)
    revision = command("git", "rev-parse", "HEAD", cwd=ROOT)
    def source_hashes():
        paths = command("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *SOURCE_PATHS, cwd=ROOT).split("\0")
        return {p: sha(ROOT / p) for p in paths if p and (ROOT / p).is_file()}
    hashes = source_hashes()
    archive_untracked_sources(out / "untracked-sources.tar")
    (out / "source.diff").write_bytes(subprocess.run(["git", "diff", "--binary", "HEAD", "--", *SOURCE_PATHS],
                                        cwd=ROOT, capture_output=True, check=True).stdout)
    env = dict(os.environ, PAW_DEV="1", PAW_DSYM="1", PAW_BUNDLE_ID=BENCH_ID, PAW_APP_NAME="paw Bench",
               PAW_ARCHS=command("uname", "-m"), PAW_PROFILE="0" if args.plain else "1", PAW_SIGN_IDENTITY="paw Bench Signing")
    # codesign finds identities only on the search list: add the benchmark keychain just while signing.
    keychain = Path.home() / "Library/Keychains/paw-bench.keychain-db"
    command("security", "unlock-keychain", "-p", Path(str(keychain) + ".password").read_text(), keychain)
    searched = [k for k in re.findall(r'"([^"]+)"', command("security", "list-keychains", "-d", "user")) if Path(k) != keychain]
    command("security", "list-keychains", "-d", "user", "-s", *searched, keychain)
    try:
        with (out / "build.log").open("w") as log:
            subprocess.run([str(ROOT / "scripts/bundle.sh"), str(out)], env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True, cwd=ROOT)
    finally:
        command("security", "list-keychains", "-d", "user", "-s", *searched)
    app = out / "paw.app"
    exe = app / "Contents/MacOS/paw"
    fixture = out / (FIXTURE_NAME + ".app") / "Contents"
    (fixture / "MacOS").mkdir(parents=True)
    (fixture / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.pseudobun.paw.performance-fixture",
        "CFBundleName": FIXTURE_NAME, "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"}))
    source = ROOT / "Tests/Fixtures/Performance.swift"
    command("swiftc", "-O", source, "-o", fixture / "MacOS/fixture")
    compile_driver(out / "wmbench")
    uuids = command("xcrun", "dwarfdump", "--uuid", exe)
    require(source_hashes() == hashes and command("git", "rev-parse", "HEAD", cwd=ROOT) == revision,
            "source/revision changed while building; retain this failed artifact and rebuild with a new label")
    save(out / "build.json", {"schema": 1, "revision": revision,
         "driver_sha256": sha(out / "wmbench"), "source_hashes": hashes, "binary_sha256": sha(exe), "uuids": uuids,
         "dsym_sha256": sha(out / "paw.dSYM/Contents/Resources/DWARF/paw"),
         "untracked_sources_sha256": sha(out / "untracked-sources.tar"),
         "fixture_source_sha256": sha(source), "fixture_sha256": sha(fixture / "MacOS/fixture"),
         "instrumented": not args.plain, "environment": environment(),
         "signature": subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                                      text=True, capture_output=True, check=True).stderr})
    print(f"Prepared {out}; nothing installed, launched or measured.")


def ipc(path, text):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(10)
        client.connect(str(path))
        client.sendall(text.encode())
        client.shutdown(socket.SHUT_WR)
        chunks, length = [], 0
        while chunk := client.recv(65536):
            length += len(chunk)
            require(length <= 16 * 1024 * 1024, "oversized IPC reply")
            chunks.append(chunk)
    result = json.loads(b"".join(chunks))
    require(not result.get("error"), f"PAW: {result.get('error')}")
    return result


def main_apps():
    """Running PAW apps of this user; CLI processes such as a status bar's `paw subscribe` are not apps."""
    output = command("ps", "-axww", "-o", "uid=,pid=,command=")
    lib = ctypes.CDLL("/usr/lib/libproc.dylib")
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    apps = []
    for line in output.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and int(parts[0]) == os.getuid():
            # Resolve the executable independently of launch arguments and spaces in app names.
            buffer = ctypes.create_string_buffer(4096)
            pid = int(parts[1])
            if lib.proc_pidpath(pid, buffer, len(buffer)) > 0:
                exe = Path(os.fsdecode(buffer.value))
                # LaunchServices starts apps by their full path with no command; options start with "-".
                if exe.name == "paw" and (parts[2] == str(exe) or parts[2].startswith(str(exe) + " -")):
                    app = exe.parents[2] if str(exe).endswith("/Contents/MacOS/paw") else exe.parent
                    apps.append((pid, app))
    return apps


def current_user(name):
    """Deliberate opt-in: --user must name this login. Returns the identity kept with each session."""
    require(sys.platform == "darwin" and os.getuid() != 0, "run as yourself on macOS, not root")
    actual = pwd.getpwuid(os.getuid())
    require(name == actual.pw_name == getpass.getuser(), "--user must name the current login")
    require(Path.home() == Path(actual.pw_dir), "HOME must be this user's actual home")
    require(command("stat", "-f", "%Su", "/dev/console") == name, "this user must own the active console")
    logged_in = {line.split()[0] for line in command("who").splitlines() if line.split()}
    require(not (logged_in - {name, "root"}), "log out other users first; fast switching is insufficient")
    agent = subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/com.pseudobun.paw"], capture_output=True)
    require(agent.returncode != 0, "PAW's launchd supervisor would restart PAW mid-run; stop it first")
    help_text = subprocess.run(["open", "--help"], text=True, capture_output=True)
    require("--env" in help_text.stdout + help_text.stderr, "this runner requires open --env support")
    return {"user": actual.pw_name, "uid": actual.pw_uid, "home": actual.pw_dir}


def bench_app():
    return Path.home() / "Applications/paw Bench.app"


def config(windows, scene):
    rules = [{"app": FIXTURE_NAME, "title": f"PAW Perf {i:02}", "workspace": "1" if i <= windows // 2 else "2"}
             for i in range(1, windows + 1)]
    rules.append({"app": "/^(?!PAW Performance Fixture$).*/", "manage": False})
    return {"layout": {"default": "columns", "workspaces": 2, "windowServer": False,
                       "minTileWidth": 0, "minTileHeight": 0},
            "rules": rules, "bindings": {}, "hooks": {}, "setups": {}, "workspaces": {},
            "focus": {"mouseFollowsFocus": False, "focusFollowsMouse": False},
            "animation": {"enabled": True, "durationMs": 180, "resize": "start", "maxWindows": 12},
            "overview": {"thumbnails": "on" if scene == "overview-on" else "off"},
            "updates": {"check": False, "automatic": False}, "openAtLogin": False}


def wait_for(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise RuntimeError(message)


class Fixture:
    def __init__(self, exe, count, log):
        self.process = subprocess.Popen([str(exe), str(count)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=log, text=True, bufsize=1)

    def state(self):
        require(self.process.poll() is None, "fixture exited")
        self.process.stdin.write("state\n")
        self.process.stdin.flush()
        require(select.select([self.process.stdout], [], [], 10)[0], "fixture response timeout")
        result = json.loads(self.process.stdout.readline())
        require(result.get("schema") == 1, "unsupported fixture state")
        return result

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write("quit\n")
                self.process.stdin.flush()
                self.process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                self.process.terminate()
                self.process.wait(timeout=5)
        self.process.stdin.close()
        self.process.stdout.close()


class Trace:
    """Wait for xctrace's documented Darwin start notification, not a guessed delay."""
    def __init__(self, pid, path, template, log):
        self.lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
        self.lib.notify_register_file_descriptor.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int),
                                                            ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
        self.token, self.fd = ctypes.c_int(), ctypes.c_int(-1)
        name = ("com.pseudobun.paw.perf." + uuid.uuid4().hex).encode()
        require(self.lib.notify_register_file_descriptor(name, ctypes.byref(self.fd), 0, ctypes.byref(self.token)) == 0,
                "notify registration failed")
        self.process, self.closed = None, False
        try:
            self.process = subprocess.Popen(["xcrun", "xctrace", "record", "--template", template,
                "--instrument", "os_signpost", "--attach", str(pid), "--output", str(path),
                "--notify-tracing-started", name.decode(), "--time-limit", "1h"], stdout=log, stderr=log)

            def ready():
                require(self.process.poll() is None, "xctrace exited before capture started; read xctrace.log")
                if select.select([self.fd.value], [], [], 0)[0]:
                    require(len(os.read(self.fd.value, 4)) == 4, "invalid trace-start notification")
                    return True
                return False
            wait_for(ready, 60, "xctrace start notification timed out")
        except BaseException:
            self.close()
            raise

    def close(self):
        if self.closed: return
        self.closed = True
        try:
            if self.process is not None:
                if self.process.poll() is None:
                    self.process.send_signal(signal.SIGINT)
                try:
                    self.process.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    self.process.terminate()
                    try: self.process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self.process.kill(); self.process.wait()
                    raise RuntimeError("xctrace did not finish; partial trace is not a valid batch")
                require(self.process.returncode in (0, 130, -signal.SIGINT), "xctrace capture failed; read its log")
        finally:
            self.lib.notify_cancel(self.token)


def parked(frame, screen, tolerance=4):
    """As in BenchSupport.swift: macOS clamps a parked window to about a title bar and may keep its size."""
    width = min(frame["x"] + frame["w"], screen["x"] + screen["w"]) - max(frame["x"], screen["x"])
    height = min(frame["y"] + frame["h"], screen["y"] + screen["h"]) - max(frame["y"], screen["y"])
    return min(width, height) <= tolerance


def check_scene(state, expected, focused=True):
    actual = {w["id"]: w for w in state["windows"]}
    require(set(actual) == set(expected), "fixture window membership changed")
    screen = state["screens"][0]  # Scenes require one display, at the origin in both coordinate spaces.
    for wid, target in expected.items():
        require(not actual[wid]["minimized"], "a fixture window was minimized")
        got = actual[wid]["frame"]
        require(parked(got, screen) if parked(target["frame"], screen) else
                all(abs(got[key] - value) <= 4 for key, value in target["frame"].items()),
                f"window {wid} has wrong actual geometry: target {target['frame']}, actual {got}")
    if focused:
        wanted = {wid for wid, w in expected.items() if w["focused"] and w["onScreen"]}
        observed = {wid for wid, w in actual.items() if w["focused"]}
        require(wanted == observed and len(wanted) == 1, "native foreground/key-window focus does not match")


def stop_candidate(app, force=False):
    candidates = [(pid, path) for pid, path in main_apps() if path == app]
    require(len(candidates) <= 1, f"multiple {app.name} processes; quit them manually")
    if not candidates: return
    pid, _ = candidates[0]
    # AppDelegate handles SIGTERM gracefully (hidden windows come back), even before its socket is ready.
    for sig in (signal.SIGTERM, signal.SIGKILL) if force else (signal.SIGTERM,):
        try: os.kill(pid, sig)
        except ProcessLookupError: return
        try: return wait_for(lambda: (pid, app) not in main_apps(), 10, f"{app.name} did not quit")
        except RuntimeError:
            if sig == signal.SIGKILL or not force: raise


def restore(app, daily):
    """Stops the disposable benchmark PAW, then reopens the PAW apps that ran before the session."""
    stop_candidate(app, force=True)  # Never two window managers; the benchmark app manages only fixtures.
    running = {path for _, path in main_apps()}
    for path in daily:
        if Path(path) not in running: command("open", path)


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def decision(calibration, pairs):
    require(len(calibration) >= 5 and len(pairs) >= 5, "need at least five calibration batches and A/B pairs")
    require(all(number(v) and v >= 0 for v in calibration) and
            all(len(p) == 2 and all(number(v) and v >= 0 for v in p) for p in pairs), "invalid comparison values")
    noise = max(calibration) - min(calibration)
    differences = [b - a for a, b in pairs]
    delta = statistics.median(differences)
    verdict = "inconclusive"
    if noise > 0 and delta < -noise and all(v < 0 for v in differences): verdict = "improved"
    if noise > 0 and delta > noise and all(v > 0 for v in differences): verdict = "regressed"
    return {"verdict": verdict, "noise_range": noise, "median_paired_delta": delta,
            "paired_differences": differences, "rule": "range-and-consistent-pairs-v1"}


def compile_driver(output):
    command("xcrun", "swiftc", "-O", "-parse-as-library", ROOT / "scripts/bench/BenchSupport.swift",
            ROOT / "scripts/bench/wmbench.swift", "-o", output)


def query(sock):
    return json.loads(ipc(sock, "query")["json"])


def verify(sock, app, manifest, cfg):
    status = ipc(sock, "status")
    require(status["trusted"] == "yes" and not status["error"], "Accessibility/config is not ready")
    require(status["config"] == str(cfg) and status["windowMoves"].startswith("off:"), "wrong config/movement path")
    require(main_apps() == [(int(status["pid"]), app)], "unexpected PAW process or executable path")
    require(sha(app / "Contents/MacOS/paw") == manifest["binary_sha256"], "deployed PAW binary changed")
    return status


def summarize(data, workload):
    require(data.get("schema") == 1 and data.get("resources_valid") is True, "invalid recorder schema/resources")
    require(data["thermal_start"] == data["thermal_end"] == 0, "thermal state was not nominal")
    require(data["incomplete_intervals"] == data["dropped_records"] == 0, "unfinished/dropped work")
    start, end, cpu = data["start_ns"], data["end_ns"], data["cpu_seconds"]
    require(number(start) and number(end) and end > start and data["elapsed_ns"] == end - start, "bad time window")
    require(number(cpu) and cpu >= 0, "invalid CPU measurement")
    require(number(data["lifetime_peak_rss_bytes"]) and data["lifetime_peak_rss_bytes"] >= 0, "invalid lifetime peak RSS")
    require(workload["schema"] == 2 and workload["valid"] is True and workload["recording"] is True, "invalid workload")
    count, mode = workload["count"], workload["mode"]
    require(isinstance(count, int) and not isinstance(count, bool) and 2 <= count <= 10000 and count % 2 == 0, "invalid workload count")
    require(len(set(workload["window_ids"])) == len(workload["window_ids"]) > 0, "invalid workload membership")
    expected = {"switch": ["workspace"] * count, "idle": [],
                "overview-off": ["overview.open", "overview.close"] * (count // 2),
                "overview-on": ["overview.open", "overview.close"] * (count // 2),
                "ops": ["focus"] * count + ["swap"] * count + ["resize"] * count + ["layout"] * (4 * max(1, count // 8))}
    require(mode in expected and workload["expected_commands"] == expected[mode], "wrong workload command sequence")
    counters, rows = data["counters"], data["intervals"]
    require(all(isinstance(v, int) and not isinstance(v, bool) and v >= 0 for v in counters.values()), "invalid work counts")
    require(not any(v for k, v in counters.items() if "failures" in k), "work failed; not a speedup")
    seen = {}
    for row in rows:
        require(row["id"] not in seen and number(row["duration_ns"]) and row["duration_ns"] >= 0, "invalid/duplicate interval")
        require(start <= row["start_ns"] <= row["start_ns"] + row["duration_ns"] <= end, "interval outside measurement")
        seen[row["id"]] = row
    for row in rows:
        if "parent" not in row: continue
        require(row["parent"] in seen, "missing interval parent")
        parent = seen[row["parent"]]
        require(parent["start_ns"] <= row["start_ns"] and row["start_ns"] + row["duration_ns"] <= parent["start_ns"] + parent["duration_ns"], "invalid nested interval")
    commands = sorted((r for r in rows if r["name"] == "command" and "parent" not in r), key=lambda r: r["start_ns"])
    require([r["detail"] for r in commands] == workload["expected_commands"], "command count/order differs from workload")
    captures = [r for r in rows if r["name"] == "capture"]
    require(len(captures) == (workload["count"] // 2 if workload["mode"] == "overview-on" else 0), "wrong fresh capture count")
    for row in captures:
        values = row["values"]
        require(values["enumerated"] == 1 and all(values[k] == len(workload["window_ids"]) for k in ("expected", "attempted", "succeeded", "delivered")), "missing/failed thumbnails")
    if workload["mode"] in ("switch", "ops"):
        require(counters.get("ax_write_attempts", 0) > 0, "movement scene did no AX writes")
    metrics = {"cpu_seconds": cpu, "elapsed_seconds": (end - start) / 1e9,
               "cpu_per_second": cpu / ((end - start) / 1e9), "lifetime_peak_rss_bytes": data["lifetime_peak_rss_bytes"]}
    metrics.update({"count." + key: value for key, value in counters.items()})
    metrics["count.capture_batches"] = len(captures)
    for key in ("expected", "attempted", "succeeded", "delivered"):
        metrics["count.capture_" + key] = sum(r["values"][key] for r in captures)
    groups = {}
    for row in rows:
        if row["name"] == "command" and "parent" in row: continue
        key = row["name"] + ("." + row["detail"] if row["detail"] else "")
        groups.setdefault(key, []).append(row["duration_ns"] / 1e6)
    for key, values in groups.items(): metrics[key + ".median_ms"] = statistics.median(values)
    observed = {}
    for sample in workload["samples"]:
        require(number(sample["elapsed_ms"]) and sample["elapsed_ms"] >= 0, "invalid latency sample")
        observed.setdefault(sample["metric"], []).append(sample["elapsed_ms"])
    wanted = {"switch": {"switch.round_trip": count, "switch.geometry": count}, "idle": {},
              "overview-off": {"overview.open.round_trip": count // 2, "overview.close.round_trip": count // 2},
              "overview-on": {"overview.open.round_trip": count // 2, "overview.close.round_trip": count // 2},
              "ops": {"focus.round_trip": count, "swap.round_trip": count, "resize.round_trip": count,
                      "layout.round_trip": 4 * max(1, count // 8), "query.round_trip": count}}
    require({k: len(v) for k, v in observed.items()} == wanted[mode], "missing/extra latency samples")
    for key, values in observed.items(): metrics[key + ".median_ms"] = statistics.median(values)
    return metrics


def primary(scene):
    return {"switch": "cpu_seconds", "ops": "cpu_seconds", "idle": "cpu_per_second",
            "overview-off": "command.overview.open.median_ms", "overview-on": "capture.median_ms"}[scene]


def read_metrics(directory, item, settings):
    relative = Path(item["path"])
    path = (directory / relative).resolve()
    require(not relative.is_absolute() and ".." not in relative.parts and path != directory.resolve()
            and path.is_relative_to(directory.resolve()), "unsafe batch path")
    stored = load(path / "result.json")
    require(stored["valid"] is True and stored["metrics"] is not None, "batch lacks valid measured metrics")
    workload = load(path / "workload.json")
    require(workload["mode"] == settings["scene"] and workload["count"] == settings["iterations"] * 2
            and len(workload["window_ids"]) == settings["windows"]
            and all(workload[k] == settings[k] for k in ("pace", "settle", "duration")), "batch workload differs from session")
    actual = summarize(load(path / "measurement.json"), workload)
    require(stored["metrics"] == actual, "summary differs from raw measurements")
    return actual


def session_summary(directory, record):
    lines = ["# PAW benchmark session", "", "Measured internal CPU/latency and actual geometry; no presented-frame claim.", ""]
    for side in ("a", "b"):
        results = [load(directory / b["path"] / "result.json")["metrics"] for b in record["batches"] if b["side"] == side]
        if not results: continue
        if any(r is None for r in results):
            lines += ["Plain diagnostic run; inspect its trace and workload.json. No numeric verdict.", ""]; continue
        lines += [f"## Side {side}", "", "| Metric (units in name) | Median | Batches with data |", "|---|---:|---:|"]
        for key in sorted({k for r in results for k in r}):
            values = [r.get(key, 0 if key.startswith("count.") else None) for r in results]
            values = [v for v in values if v is not None]
            lines.append(f"| {key} | {statistics.median(values):.6g} | {len(values)} |")
        lines.append("")
    (directory / "summary.md").write_text("\n".join(lines) + "\n")


def compare(args):
    calibration, result = load(args.calibration / "session.json"), load(args.session / "session.json")
    require(calibration["schema"] == result["schema"] == 2 and calibration["complete"] and result["complete"], "unsupported/incomplete session")
    require(calibration["signature"] == result["signature"], "environment/workload differs")
    require(calibration["builds"]["a"] == result["builds"]["a"], "calibration requires the exact base artifact")
    require(not calibration["against"] and result["against"], "need unchanged calibration and alternating A/B session")
    batches = result["signature"]["workload"]["batches"]
    for directory, session, sides in ((args.calibration, calibration, ("a",)), (args.session, result, ("a", "b"))):
        items = session["batches"]
        require(len(items) == batches * len(sides) and {(b["index"], b["side"]) for b in items}
                == {(i, s) for i in range(batches) for s in sides}, "missing/invalid batch pairing")
        require(len({(directory / b["path"]).resolve() for b in items}) == len(items), "duplicate/aliased batch paths")
    metric = primary(result["signature"]["workload"]["scene"])
    settings = result["signature"]["workload"]
    calibrated = [read_metrics(args.calibration, b, settings)[metric] for b in calibration["batches"]]
    paired = [{b["side"]: read_metrics(args.session, b, settings) for b in result["batches"] if b["index"] == i} for i in range(batches)]
    counts = sorted({k for pair in paired for metrics in pair.values() for k in metrics if k.startswith("count.")})
    output = {"metric": metric, **decision(calibrated, [(p["a"][metric], p["b"][metric]) for p in paired]),
              "work_counts": {k: [{"a": p["a"].get(k, 0), "b": p["b"].get(k, 0),
                                   "delta": p["b"].get(k, 0) - p["a"].get(k, 0)} for p in paired] for k in counts},
              "review": "Explain changed work counts and inspect other metrics before accepting a speedup."}
    print(json.dumps(output, indent=2))


def install(artifact, app):
    """Fresh benchmark app, data and cache; only paths owned by BENCH_ID are replaced."""
    support = Path.home() / "Library/Application Support" / BENCH_ID
    cache = Path.home() / "Library/Caches" / BENCH_ID
    require(not any(path == app for _, path in main_apps()), "paw Bench is already running")
    for path in (app, support, cache):
        require(not path.is_symlink() and (not path.exists() or path.is_dir()), "benchmark paths must be real directories")
        require(path.resolve().is_relative_to(Path.home().resolve()), "benchmark path escapes this user's home")
    if app.exists():
        require(plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"] == BENCH_ID, "refusing to replace an unrelated app")
    for path in (app, support, cache):
        if path.exists(): shutil.rmtree(path)
    app.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", str(artifact / "paw.app"), str(app)], check=True)
    return support / "paw.sock"


def grant(args):
    """One-time privacy grants for paw Bench, launched with a config that manages no window."""
    current_user(args.user)
    app, artifact = bench_app(), args.builds.resolve() / label(args.label)
    with ExitStack() as cleanup:
        directory = Path(cleanup.enter_context(tempfile.TemporaryDirectory()))
        cfg = directory / "config.json5"; save(cfg, dict(config(2, "switch"), rules=[{"app": "/.*/", "manage": False}]))
        sock = install(artifact, app)
        cleanup.callback(stop_candidate, app, True)
        command("open", "-n", "--env", f"PAW_CONFIG={cfg}", "--env", f"PAW_PERF_OUTPUT={directory / 'unused.json'}", app)
        wait_for(sock.exists, 15, "paw Bench socket did not appear")
        ipc(sock, "settings general")
        print("In paw Bench's Settings > General, request Accessibility (and Screen Recording for overview-on), "
              "then enable paw Bench in System Settings. Waiting up to 15 minutes...", flush=True)
        wait_for(lambda: ipc(sock, "status")["trusted"] == "yes", 900, "Accessibility was not granted")
        print(f"Accessibility granted; Screen Recording: {ipc(sock, 'perf status')['screenRecording']}")


def record_batch(artifact, tools_artifact, args, directory, app):
    directory.mkdir()
    cfg = directory / "config.json5"; save(cfg, config(args.windows, args.scene))
    require(not main_apps(), "another PAW is running; the session stops it first")
    load_average = os.getloadavg()
    sock = install(artifact, app)
    manifest = load(artifact / "build.json")
    with ExitStack() as cleanup:
        cleanup.enter_context((directory / "app.log").open("w"))
        cleanup.callback(stop_candidate, app)  # Also covers a launch that never creates its socket.
        command("open", "-n", "--env", f"PAW_CONFIG={cfg}", "--env", f"PAW_PERF_OUTPUT={directory / 'measurement.json'}",
                "--stdout", directory / "app.log", "--stderr", directory / "app.log", app,
                "--args", "-overviewMode", "stage", "-overviewCanvasZoom", "0.45")
        wait_for(lambda: sock.exists(), 15, "candidate socket did not appear")
        before = verify(sock, app, manifest, cfg); save(directory / "before.json", before)
        if manifest["instrumented"] and args.scene == "overview-on":
            require(ipc(sock, "perf status")["screenRecording"], "grant Screen Recording before recording overview-on")
        fixture_log = cleanup.enter_context((directory / "fixture.log").open("w"))
        fixture = Fixture(tools_artifact / (FIXTURE_NAME + ".app") / "Contents/MacOS/fixture", args.windows, fixture_log)
        cleanup.callback(fixture.close)
        state = fixture.state()
        require(len(state["screens"]) == 1, "controlled scenes require one display")
        save(directory / "fixture-environment.json", {k: state[k] for k in ("screens", "appearance")})
        def ready():
            rows = query(sock)
            managed = [w for s in rows for w in s["windows"]]
            return len(managed) == args.windows and all(w["app"] == FIXTURE_NAME for w in managed)
        wait_for(ready, 20, "fixture membership was not adopted")
        rows = query(sock)
        require({s["id"] for s in rows} == {"1", "2"} and all(len(s["windows"]) == args.windows // 2 for s in rows), "wrong workspace distribution")
        require({w["id"] for s in rows for w in s["windows"]} == {w["id"] for w in state["windows"]}, "wrong fixture IDs")
        require(all({w["title"] for w in s["windows"]} == {f"PAW Perf {i:02}" for i in range(1, args.windows + 1)
                    if (i <= args.windows // 2) == (s["id"] == "1")} for s in rows), "fixture routing differs from the fixed scene")
        trace = None
        if args.trace:
            xlog = cleanup.enter_context((directory / "xctrace.log").open("w"))
            trace = Trace(int(before["pid"]), directory / "profile.trace", "Time Profiler", xlog)
            cleanup.callback(trace.close)
        workload_log = cleanup.enter_context((directory / "workload.log").open("w"))
        invocation = [str(tools_artifact / "wmbench"), args.scene, str(args.iterations * 2), "--pace", str(args.pace),
                      "--settle", str(args.settle), "--duration", str(args.duration), "--output", str(directory / "workload.json")]
        if manifest["instrumented"]: invocation.append("--record")
        subprocess.run(invocation, stdout=workload_log, stderr=workload_log, check=True, timeout=3000,
                       env=dict(os.environ, PAW_BENCH_SOCKET=str(sock)))
        save(directory / "after.json", verify(sock, app, manifest, cfg))
        expected = {w["id"]: w for s in query(sock) for w in s["windows"]}
        check_scene(fixture.state(), expected)
        if trace:
            require(trace.process.poll() is None, "trace ended before the scene")
            trace.close()
            subprocess.run(["xcrun", "xctrace", "symbolicate", "--input", str(directory / "profile.trace"),
                            "--output", str(directory / "profile-symbolicated.trace"), "--dsym", str(artifact / "paw.dSYM")],
                           stdout=xlog, stderr=xlog, check=True)
            require((directory / "profile.trace").exists() and (directory / "profile-symbolicated.trace").exists(), "missing trace/symbolicated output")
        metrics = summarize(load(directory / "measurement.json"), load(directory / "workload.json")) if manifest["instrumented"] else None
        result = {"valid": True, "metrics": metrics, "environment": load(directory / "fixture-environment.json"),
                  "load_average_before": load_average}
        save(directory / "result.json", result)
    return result


def run(args):
    account = current_user(args.user)
    require(2 <= args.windows <= 32 and args.windows % 2 == 0, "need an even 2–32 windows")
    require(1 <= args.batches <= 20 and 1 <= args.iterations <= 100, "batch/iteration count out of range")
    require(all(number(v) for v in (args.pace, args.settle, args.duration)) and 2 <= args.pace <= 60
            and 2 <= args.settle <= 60 and 1 <= args.duration <= 600, "invalid spacing/drain/duration")
    require(8 * args.iterations * 2 * (args.pace + 3) + args.duration + args.settle < 3000, "scene exceeds safety limit")
    builds = {s: args.builds.resolve() / label(n) for s, n in (("a", args.label), ("b", args.against)) if n}
    manifests = {s: load(path / "build.json") for s, path in builds.items()}
    for side, path in builds.items():
        m = manifests[side]
        require(m["schema"] == 1, "unsupported build manifest")
        require(m["source_hashes"]["scripts/bench/bench.py"] == sha(Path(__file__)), "use the controller archived with these sources")
        for relative, key in (("paw.app/Contents/MacOS/paw", "binary_sha256"), ("paw.dSYM/Contents/Resources/DWARF/paw", "dsym_sha256"),
                              (FIXTURE_NAME + ".app/Contents/MacOS/fixture", "fixture_sha256"), ("wmbench", "driver_sha256")):
            require(sha(path / relative) == m[key], f"archived {relative} changed")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(path / "paw.app")], check=True)
        signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(path / "paw.app")], capture_output=True, text=True, check=True).stderr
        require("Signature=adhoc" not in signature and "Authority=" in signature, "use a stable signing certificate; ad-hoc candidates refused")
    base = manifests["a"]
    require(all(m["instrumented"] for m in manifests.values()) or (not args.against and args.trace
            and args.scene in ("switch", "ops", "idle")), "plain builds are trace-only pilots")
    for m in manifests.values():
        require(m["fixture_source_sha256"] == base["fixture_source_sha256"]
                and all(m["source_hashes"][p] == base["source_hashes"][p] for p in ("scripts/bench/BenchSupport.swift", "scripts/bench/wmbench.swift"))
                and all(m["environment"][k] == base["environment"][k] for k in ("xcode", "swift", "architecture"))
                and re.findall(r"^(?:Authority|TeamIdentifier)=.*$", m["signature"], re.M)
                == re.findall(r"^(?:Authority|TeamIdentifier)=.*$", base["signature"], re.M), "toolchain, driver, fixture or signing identity differs")
    os.umask(0o077)
    session = args.runs.expanduser().resolve() / (dt.datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8])
    session.mkdir(parents=True, exist_ok=False)
    env = environment()
    workload = {k: getattr(args, k) for k in ("scene", "windows", "batches", "iterations", "pace", "settle", "duration", "trace")}
    signature = {"workload": workload, "config": config(args.windows, args.scene), "controller_sha256": sha(Path(__file__)),
                 "driver_sha256": base["driver_sha256"], "fixture_sha256": base["fixture_sha256"],
                 "environment": {k: v for k, v in env.items() if k != "power"}}
    record = {"schema": 2, "signature": signature, "account": account, "environment": env,
              "builds": {s: m["binary_sha256"] for s, m in manifests.items()}, "against": bool(args.against), "batches": [], "complete": False}
    save(session / "session.json", record)
    app = bench_app()
    apps = main_apps()
    require(all(path != app for _, path in apps), "paw Bench is already running; quit it first")
    daily = sorted({str(path) for _, path in apps})
    record["restored_apps"] = daily; save(session / "session.json", record)
    # Its own session and an EOF pipe: restoration also runs after Terminal close or this controller's SIGKILL.
    restorer = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_restore", str(app), json.dumps(daily)],
                                stdin=subprocess.PIPE, start_new_session=True)
    with ExitStack() as cleanup, subprocess.Popen(["caffeinate", "-di", "-w", str(os.getpid())]) as awake:
        @cleanup.callback
        def restored():
            restorer.stdin.close()
            restorer.wait(timeout=60)
            require(restorer.returncode == 0, "restoring PAW failed; reopen your PAW app and quit paw Bench manually")
        try:
            for path in daily: stop_candidate(Path(path))  # Graceful quit puts the daily PAW's hidden windows back.
            for index in range(args.batches):
                for side in (("a", "b") if index % 2 == 0 else ("b", "a")) if args.against else ("a",):
                    name = f"{index + 1:02}-{side}"
                    result = record_batch(builds[side], builds["a"], args, session / name, app)
                    current = environment()
                    require(all(current[k] == env[k] for k in env if k != "power"), "machine/power settings changed")
                    if "screens" not in signature: signature.update(result["environment"])
                    require(all(signature[k] == result["environment"][k] for k in ("screens", "appearance")), "display/appearance changed")
                    record["batches"].append({"index": index, "side": side, "path": name})
                    save(session / "session.json", record)
            session_summary(session, record)
            record["complete"] = True; save(session / "session.json", record)
            print(f"Measured session: {session}")
        except BaseException as error:
            save(session / "failure.json", {"errors": error_chain(error)})
            raise
        finally:
            if awake.poll() is None: awake.terminate()


def identity(pid):
    info = command("ps", "-p", pid, "-o", "uid=", "-o", "lstart=", check=False).split(None, 1)
    if len(info) != 2: return None
    lib = ctypes.CDLL("/usr/lib/libproc.dylib")
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    buffer = ctypes.create_string_buffer(4096)
    if lib.proc_pidpath(int(pid), buffer, len(buffer)) <= 0: return None
    return [int(pid), int(info[0]), info[1], os.fsdecode(buffer.value)]


def resume(targets):
    for target in targets:
        if identity(target[0]) == target and target[1] == os.getuid():
            try: os.kill(target[0], signal.SIGCONT)
            except ProcessLookupError: pass


def hung(driver, name):
    require(os.getuid() != 0, "do not run hung diagnostics as root")
    sock = Path(os.environ.get("PAW_BENCH_SOCKET") or Path.home() / "Library/Application Support" / DEV_ID / "paw.sock")
    server = int(ipc(sock, "status")["pid"])
    targets = [identity(int(p)) for p in command("pgrep", "-u", os.getuid(), "-x", re.escape(name), check=False).splitlines()]
    require(targets and all(t and t[1] == os.getuid() and t[0] not in (os.getpid(), server)
                           and Path(t[3]).name != "paw" for t in targets), "target must be another app owned by this user")
    # A separate session and EOF pipe survive Terminal close and even this controller's SIGKILL.
    watcher = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_resume", json.dumps(targets)],
                               stdin=subprocess.PIPE, start_new_session=True)
    try:
        ipc(sock, "run workspace 1; layout bsp")
        for target in targets:
            require(identity(target[0]) == target, "target identity changed")
            os.kill(target[0], signal.SIGSTOP)
        subprocess.run([str(driver), "hung", "--paused"], check=True, timeout=180)
    finally:
        try: resume(targets)
        finally:
            watcher.stdin.close()
            watcher.wait(timeout=15)
            require(watcher.returncode == 0, "resume watchdog failed; verify the target app is running")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "_resume":
        targets = json.loads(sys.argv[2]); sys.stdin.buffer.read(); resume(targets); return
    if len(sys.argv) > 1 and sys.argv[1] == "_restore":
        sys.stdin.buffer.read(); restore(Path(sys.argv[2]), json.loads(sys.argv[3])); return
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    p = sub.add_parser("prepare", help="compile/archive only; never launch or measure")
    p.add_argument("label"); p.add_argument("--plain", action="store_true")
    p.add_argument("--builds", type=Path, default=ROOT / "build.noindex/bench/builds")
    p = sub.add_parser("grant", help="LIVE: opens paw Bench, managing no window, for its one-time privacy grants")
    p.add_argument("label"); p.add_argument("--user", required=True)
    p.add_argument("--builds", type=Path, default=ROOT / "build.noindex/bench/builds")
    p = sub.add_parser("run", help="LIVE: quits your PAW, runs paw Bench with fixtures, then reopens your PAW")
    p.add_argument("label"); p.add_argument("--against"); p.add_argument("--user", required=True)
    p.add_argument("--builds", type=Path, default=ROOT / "build.noindex/bench/builds")
    p.add_argument("--runs", type=Path, default=Path.home() / "Library/Logs/paw-bench")
    p.add_argument("--scene", choices=SCENES, default="switch"); p.add_argument("--trace", action="store_true")
    p.add_argument("--windows", type=int, default=8); p.add_argument("--iterations", type=int, default=10)
    p.add_argument("--batches", type=int, default=5); p.add_argument("--pace", type=float, default=2)
    p.add_argument("--settle", type=float, default=3); p.add_argument("--duration", type=float, default=120)
    p = sub.add_parser("compare", help="read-only comparison of unchanged calibration and A/B session")
    p.add_argument("calibration", type=Path); p.add_argument("session", type=Path)
    p = sub.add_parser("hung", help="LIVE: pauses another app, with an independent resume watchdog")
    p.add_argument("app")
    sub.add_parser("check", help="run controller and pure Swift unit checks; no PAW/fixture launch")
    args = parser.parse_args()
    if args.action in ("run", "hung"):
        def interrupted(*_): raise KeyboardInterrupt()
        signal.signal(signal.SIGTERM, interrupted); signal.signal(signal.SIGHUP, interrupted)
    if args.action in ("hung", "check"):
        directory = ROOT / "build.noindex/bench"; directory.mkdir(parents=True, exist_ok=True)
        if args.action == "hung":
            compile_driver(directory / "wmbench"); hung(directory / "wmbench", args.app)
        else:
            command("xcrun", "swiftc", "-parse-as-library", ROOT / "scripts/bench/BenchSupport.swift", ROOT / "Tests/Performance/BenchChecks.swift", "-o", directory / "checks")
            subprocess.run([str(directory / "checks")], check=True)
            subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "Tests/Performance", "-p", "test_*.py"], cwd=ROOT, check=True)
    else: {"prepare": build, "grant": grant, "run": run, "compare": compare}[args.action](args)


if __name__ == "__main__":
    try:
        if len(sys.argv) == 1 or sys.argv[1] in ("switch", "ops", "all"):
            directory = ROOT / "build.noindex/bench"; directory.mkdir(parents=True, exist_ok=True)
            compile_driver(directory / "wmbench")
            subprocess.run([str(directory / "wmbench"), *sys.argv[1:]], check=True, timeout=3000)
        else: main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        for message in error_chain(error): print("PAW bench: " + message, file=sys.stderr)
        sys.exit(1)
