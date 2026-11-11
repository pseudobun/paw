"""Controller checks with synthetic records and mocked processes; no desktop benchmark."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

SPEC = importlib.util.spec_from_file_location("paw_bench", Path(__file__).resolve().parents[2] / "scripts/bench/bench.py")
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)


def measurement(mode="switch"):
    commands = {"switch": ["workspace"] * 2, "idle": [], "overview-on": ["overview.open", "overview.close"],
                "overview-off": ["overview.open", "overview.close"],
                "ops": ["focus"] * 2 + ["swap"] * 2 + ["resize"] * 2 + ["layout"] * 4}[mode]
    counts = {"switch": {"switch.round_trip": 2, "switch.geometry": 2}, "idle": {},
              "overview-off": {"overview.open.round_trip": 1, "overview.close.round_trip": 1},
              "overview-on": {"overview.open.round_trip": 1, "overview.close.round_trip": 1},
              "ops": {"focus.round_trip": 2, "swap.round_trip": 2, "resize.round_trip": 2, "layout.round_trip": 4, "query.round_trip": 2}}[mode]
    workload = {"schema": 2, "valid": True, "recording": True, "mode": mode, "count": 2, "pace": 2, "settle": 3,
                "duration": 120, "window_ids": list(range(1, 9)), "expected_commands": commands,
                "samples": [{"metric": k, "elapsed_ms": i + 1} for k, n in counts.items() for i in range(n)]}
    data = {"schema": 1, "resources_valid": True, "thermal_start": 0, "thermal_end": 0, "start_ns": 1000,
            "end_ns": 10_001_000, "elapsed_ns": 10_000_000, "cpu_seconds": 0.005, "lifetime_peak_rss_bytes": 4096,
            "incomplete_intervals": 0, "dropped_records": 0, "counters": {"ax_write_attempts": 8},
            "intervals": [{"id": i + 1, "name": "command", "detail": c, "start_ns": 1000 + i * 1000,
                           "duration_ns": 100, "values": {}} for i, c in enumerate(commands)]}
    if mode == "overview-on":
        data["intervals"].append({"id": 3, "name": "capture", "detail": "", "start_ns": 3000, "duration_ns": 100,
                                  "values": {"enumerated": 1, "expected": 8, "attempted": 8, "succeeded": 8, "delivered": 8}})
    return data, workload


class MeasurementTests(unittest.TestCase):
    def test_units_counts_and_all_scene_contracts(self):
        for scene in bench.SCENES:
            data, workload = measurement(scene)
            result = bench.summarize(data, workload)
            self.assertEqual(result["elapsed_seconds"], 0.01)
            self.assertEqual(result["cpu_per_second"], 0.5)
            self.assertEqual(result["count.ax_write_attempts"], 8)
        data, workload = measurement("overview-off")
        data["intervals"][1]["duration_ns"] = 900
        result = bench.summarize(data, workload)
        self.assertEqual(result[bench.primary("overview-off")], 0.0001)
        self.assertEqual(result["command.overview.close.median_ms"], 0.0009)

    def test_failed_incomplete_or_partial_work_rejected(self):
        for field, value in (("resources_valid", False), ("cpu_seconds", float("nan")), ("thermal_end", 2),
                             ("incomplete_intervals", 1), ("dropped_records", 1), ("schema", 99)):
            data, workload = measurement(); data[field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError): bench.summarize(data, workload)
        for change in ("command", "sample", "failure", "outside", "membership"):
            data, workload = measurement()
            if change == "command": workload["expected_commands"].pop()
            if change == "sample": workload["samples"].pop()
            if change == "failure": data["counters"]["ax_write_failures"] = 1
            if change == "outside": data["intervals"][0]["start_ns"] = 0
            if change == "membership": workload["window_ids"].append(1)
            with self.subTest(change=change), self.assertRaises(RuntimeError): bench.summarize(data, workload)

    def test_nested_commands_and_fresh_captures(self):
        data, workload = measurement()
        nested = dict(data["intervals"][0], id=3, parent=1, duration_ns=50)
        data["intervals"].append(nested)
        bench.summarize(data, workload)
        nested["parent"] = 99
        with self.assertRaises(RuntimeError): bench.summarize(data, workload)
        data, workload = measurement("overview-on")
        self.assertEqual(bench.summarize(data, workload)["count.capture_delivered"], 8)
        data["intervals"][-1]["values"]["delivered"] = 7
        with self.assertRaises(RuntimeError): bench.summarize(data, workload)

    def test_decision_requires_calibration_and_consistent_pairs(self):
        c = [9, 10, 11, 10, 9]
        for pairs, verdict in (([(10, 6)] * 5, "improved"), ([(10, 14)] * 5, "regressed"),
                               ([(10, 9)] * 5, "inconclusive"), ([(10, 6)] * 4 + [(10, 11)], "inconclusive")):
            self.assertEqual(bench.decision(c, pairs)["verdict"], verdict)
        self.assertEqual(bench.decision([10] * 5, [(10, 6)] * 5)["verdict"], "inconclusive")
        with self.assertRaises(RuntimeError): bench.decision(c[:4], [(10, 6)] * 5)


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.args = SimpleNamespace(calibration=root / "aa", session=root / "ab")
        settings = {"scene": "switch", "iterations": 1, "windows": 8, "batches": 5, "pace": 2, "settle": 3, "duration": 120, "trace": False}
        for directory, against in ((self.args.calibration, False), (self.args.session, True)):
            directory.mkdir()
            session = {"schema": 2, "complete": True, "against": against, "signature": {"workload": settings},
                       "builds": {"a": "base", "b": "candidate"} if against else {"a": "base"}, "batches": []}
            for index in range(5):
                for side in (("a", "b") if index % 2 == 0 else ("b", "a")) if against else ("a",):
                    name = f"{index + 1:02}-{side}"; path = directory / name; path.mkdir()
                    data, workload = measurement()
                    data["cpu_seconds"] = (0.001 if side == "b" else 0.006) if against else [0.005, 0.006, 0.007, 0.006, 0.005][index]
                    if side == "b": data["counters"].update(ax_write_attempts=6, ax_coalesced=2)
                    bench.save(path / "workload.json", workload); bench.save(path / "measurement.json", data)
                    bench.save(path / "result.json", {"valid": True, "metrics": bench.summarize(data, workload)})
                    session["batches"].append({"index": index, "side": side, "path": name})
            bench.save(directory / "session.json", session)

    def compare(self):
        with contextlib.redirect_stdout(io.StringIO()) as output: bench.compare(self.args)
        return json.loads(output.getvalue())

    def test_pairs_by_identity_and_surfaces_counts(self):
        path = self.args.session / "session.json"; session = bench.load(path)
        session["batches"].reverse(); bench.save(path, session)
        result = self.compare()
        self.assertEqual(result["verdict"], "improved")
        self.assertEqual(result["work_counts"]["count.ax_write_attempts"], [{"a": 8, "b": 6, "delta": -2}] * 5)
        self.assertEqual(result["work_counts"]["count.ax_coalesced"], [{"a": 0, "b": 2, "delta": 2}] * 5)

    def test_pairing_paths_base_and_signature_guards(self):
        path = self.args.session / "session.json"; original = bench.load(path)
        (self.args.session / "alias").symlink_to(self.args.session / "01-a", target_is_directory=True)
        for change in ("side", "index", "path", "alias", "base", "signature", "incomplete", "missing"):
            value = copy.deepcopy(original)
            if change == "side": value["batches"][0]["side"] = "wrong"
            if change == "index": value["batches"][0]["index"] = 99
            if change == "path": value["batches"][0]["path"] = "../aa/01-a"
            if change == "alias": value["batches"][1]["path"] = "alias"
            if change == "base": value["builds"]["a"] = "other"
            if change == "signature": value["signature"]["other"] = True
            if change == "incomplete": value["complete"] = False
            if change == "missing": value["batches"].pop()
            bench.save(path, value)
            with self.subTest(change=change), self.assertRaises(RuntimeError): self.compare()

    def test_summary_raw_and_workload_are_rechecked(self):
        path = self.args.session / "01-b/result.json"; original = bench.load(path)
        edited = copy.deepcopy(original); edited["metrics"]["count.ax_write_attempts"] = 999; bench.save(path, edited)
        with self.assertRaisesRegex(RuntimeError, "summary differs"): self.compare()
        bench.save(path, original)
        path = self.args.session / "01-b/workload.json"; value = bench.load(path); value["pace"] = 3; bench.save(path, value)
        with self.assertRaisesRegex(RuntimeError, "workload differs"): self.compare()


class SafetyTests(unittest.TestCase):
    def test_cleanup_error_chain_keeps_initial_failure(self):
        try:
            try: raise RuntimeError("socket missing")
            finally: raise RuntimeError("cleanup failed")
        except RuntimeError as error:
            self.assertEqual(bench.error_chain(error), ["socket missing", "cleanup failed"])

    def test_private_distinct_account_registration(self):
        with tempfile.TemporaryDirectory() as directory:
            actual = SimpleNamespace(pw_name="pawperf", pw_uid=os.getuid(), pw_dir=directory)
            daily = SimpleNamespace(pw_name="daily", pw_uid=os.getuid() + 1)
            marker = Path(directory) / bench.ACCOUNT_MARKER
            with self.assertRaises(RuntimeError): bench.account_registration(marker, actual)
            with patch.object(bench, "local_test_user", return_value=actual), patch.object(bench.pwd, "getpwnam", return_value=daily), contextlib.redirect_stdout(io.StringIO()):
                args = SimpleNamespace(test_user="pawperf", daily_user="daily"); bench.register_test_user(args)
                bench.account_registration(marker, actual)
                with self.assertRaises(FileExistsError): bench.register_test_user(args)
                marker.chmod(0o644)
                with self.assertRaises(RuntimeError): bench.account_registration(marker, actual)
                marker.chmod(0o600)
                with patch.object(bench.pwd, "getpwnam", return_value=actual):
                    with self.assertRaises(RuntimeError): bench.account_registration(marker, actual)
                    marker.unlink()
                    with self.assertRaises(RuntimeError): bench.register_test_user(args)
            self.assertFalse(marker.exists())

    def test_admin_and_wrong_login_refused(self):
        actual = SimpleNamespace(pw_name="pawperf", pw_uid=501, pw_dir="/Users/pawperf")
        with patch.object(bench.sys, "platform", "darwin"), patch.object(bench.os, "getuid", return_value=501), patch.object(bench.pwd, "getpwuid", return_value=actual), patch.object(bench.getpass, "getuser", return_value="pawperf"), patch.object(Path, "home", return_value=Path(actual.pw_dir)), patch.object(bench, "command", return_value="staff admin"):
            with self.assertRaises(RuntimeError): bench.local_test_user("pawperf")
            with self.assertRaises(RuntimeError): bench.local_test_user("daily")

    def test_stale_pid_is_never_resumed(self):
        target = [123, os.getuid(), "start", "/test/TextEdit"]
        with patch.object(bench, "identity", return_value=[123, os.getuid(), "new-start", "/test/TextEdit"]), patch.object(bench.os, "kill") as kill:
            bench.resume([target]); kill.assert_not_called()
        with patch.object(bench, "identity", return_value=target), patch.object(bench.os, "kill") as kill:
            bench.resume([target]); kill.assert_called_once_with(123, signal.SIGCONT)

    def test_hung_interrupt_resumes_and_closes_independent_watchdog(self):
        target = [123, os.getuid(), "start", "/test/TextEdit"]
        watcher = MagicMock(); watcher.returncode = 0
        with patch.object(bench, "command", return_value="123"), patch.object(bench, "ipc", return_value={"pid": "456"}), patch.object(bench, "identity", return_value=target), patch.object(bench.subprocess, "Popen", return_value=watcher) as spawn, patch.object(bench.subprocess, "run", side_effect=KeyboardInterrupt), patch.object(bench.os, "kill") as kill:
            with self.assertRaises(KeyboardInterrupt): bench.hung(Path("/driver"), "TextEdit")
            self.assertTrue(spawn.call_args.kwargs["start_new_session"])
            self.assertEqual([call.args for call in kill.call_args_list], [(123, signal.SIGSTOP), (123, signal.SIGCONT)])
            watcher.stdin.close.assert_called_once()
            watcher.wait.assert_called_once_with(timeout=15)

    def test_startup_timeout_cleans_candidate_by_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); artifact = root / "artifact"; artifact.mkdir()
            bench.save(artifact / "build.json", {"instrumented": True})
            args = SimpleNamespace(windows=8, scene="switch")
            with patch.object(Path, "home", return_value=root), patch.object(bench, "main_apps", return_value=[]), patch.object(bench.subprocess, "run"), patch.object(bench, "command"), patch.object(bench, "wait_for", side_effect=RuntimeError("socket missing")), patch.object(bench, "stop_candidate") as stop:
                with self.assertRaisesRegex(RuntimeError, "socket missing"):
                    bench.record_batch(artifact, artifact, args, root / "batch", root / "Applications/paw Dev.app")
                stop.assert_called_once_with(root / "Applications/paw Dev.app")

    def test_candidate_cleanup_does_not_signal_another_app(self):
        app, other = Path("/test/paw Dev.app"), Path("/Applications/paw.app")
        with patch.object(bench, "main_apps", side_effect=[[(123, app), (456, other)], [(456, other)]]), patch.object(bench.os, "kill") as kill:
            bench.stop_candidate(app); kill.assert_called_once_with(123, signal.SIGTERM)

    def test_labels_cannot_escape_build_directory(self):
        for value in ("../daily", "/tmp/test", "foo/bar", "", "."):
            with self.assertRaises(RuntimeError): bench.label(value)


if __name__ == "__main__": unittest.main()
