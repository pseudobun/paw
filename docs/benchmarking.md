# Measuring PAW changes

One entrypoint, `just bench`: the Swift driver owns workloads, and the stdlib Python controller
owns artifacts, controlled sessions, captures and comparisons. Normal builds compile the
in-app recorder out. This prepares measurement infrastructure, not an optimization.

**Draft status:** app code compiled with/without `PAW_PROFILE`; the driver and pure helper
checks compiled, and the fixture type-checked. Automated checks, signed profiling bundles,
account setup, launches, traces and benchmark scenes have not been executed. Do not treat this
as a validated regression gate until the pilot below passes. The first draft commit skips CI
to preserve the explicit request not to run tests yet; the CI check step is prepared for later.

## Quick diagnostics

These commands operate on the already-running PAW Dev and change its workspaces/layout:

```sh
just bench switch 200
just bench ops 200
just bench all 200
just bench hung TextEdit
just bench switch 200 --output /tmp/switch.json
```

They require one display and windows on workspaces 1 and 2. `ops` uses columns and alternating
east/west or positive/negative operations; a no-op fails instead of becoming a fast sample.
There are no desktop-wide quits. The hung diagnostic pauses only matching processes owned by
the current user, refusing PAW itself, and installs an independent EOF-triggered resume
watchdog before stopping them. Identity checks include PID, UID, start time and executable.
It resumes on normal exit, interruption or controller death. System shutdown, killing the
watchdog too, or losing the GUI session can still require manual recovery (`kill -CONT <pid>`).
Use disposable test documents. Hung diagnostics are not part of automated A/B classification.

Round trips include IPC/scheduling and exclude asynchronous completion. `switch.geometry`
polls WindowServer every millisecond until actual positions/sizes match within 4 points,
including hidden windows. It is not presented-frame latency. Every reply must parse and have
no application error; missing windows, timeouts and changed membership fail the run. The new
workload is version 2 and cannot use the historical `PERFORMANCE.md` tables as calibration.

## Prepare without running apps or tests

Use full Xcode/Instruments, Python 3.9+ and a stable signing certificate. The existing bundler
produces optimized Release apps, debug information and a matching dSYM before stripping its
app copy. The build command never launches, installs or measures anything:

```sh
just bench prepare plain-base --plain
just bench prepare base
# After the candidate code change, with the same compiler/signing identity:
just bench prepare candidate
```

Artifacts live in `build.noindex/bench/builds/<label>/`; labels cannot be reused. Each contains
the signed dev app, dSYM, fixture app, workload executable, source hashes, tracked dirty patch,
untracked build-input source archive, UUIDs, compiler/environment/signing metadata and build logs.
Source capture is restricted to the app/resources, package/version files, bundler, workload
controller/driver and fixture; unrelated untracked documents are not copied. Changes
to sources or revision while building fail preparation. The selected app/fixture/driver/dSYM
hashes are verified before recording. Both A/B sides use the **base artifact's exact driver
and fixture binaries**; their source and compiler versions must agree with the candidate.
Do not edit the controller between calibration and comparison.

If your checkout is private to the daily user, copy only the controller and prepared artifacts:

```sh
mkdir -p /Users/Shared/paw-bench
cp scripts/bench/bench.py /Users/Shared/paw-bench/bench.py
ditto build.noindex/bench/builds /Users/Shared/paw-bench/builds
```

The standalone copied controller supports `register`, `run --builds builds`, and `compare`.
Quick commands, `prepare`, and `check` require the source checkout. No private signing key or
second Apple Account is needed to run prepared artifacts.

## Separate local test user, later

Create a Standard local macOS user (for example `pawperf`), save your daily work, and log out
of the daily user. Fast user switching leaves it logged in. A separate local login shares the
same machine and system services, but keeps daily files, PAW state and permissions separate.
No Apple Account/iCloud sign-in is needed. The runner does not create accounts or grant access.

In that test user, explicitly register against your actual daily local login:

```sh
cd /Users/Shared/paw-bench
python3 bench.py register --test-user pawperf --daily-user YOUR_DAILY_LOGIN
```

This creates only `~/.paw-bench-test-account.json` (owned, mode 0600), recording distinct daily
and test identities. The runner refuses admins, mismatched identities/home/console, another
logged-in user, and an active PAW launch agent. Registration is deliberate opt-in, not a
sandbox against intentionally identifying the wrong accounts. If identities change, inspect
and remove the marker before registering again. No registration has been performed here.

One time, copy a prepared app to `~/Applications/paw Dev.app`, open it, grant Accessibility,
and grant Screen Recording for `overview-on`. Quit it afterward. This step launches an app;
it is intentionally left for the pilot. A stable certificate/path helps grants survive builds.
If Instruments needs Developer Tools permission for the Standard user, resolve it explicitly;
the runner never changes groups, security settings or permissions for you.

## Controlled sessions, deliberately not run yet

These commands launch apps, move windows and reset the test user's dev app/state/cache.
They require **every PAW already stopped**. There is no automatic previous-app switching or
backup/restore system. The installed release and daily user's home are outside the target
paths. The disposable test account's last candidate app/state may remain after the session.

```sh
# First, one plain trace; inspect a known PAW symbol in Instruments:
python3 bench.py run plain-base --builds builds --test-user pawperf --trace --batches 1 --iterations 2
# Then, one instrumented pilot:
python3 bench.py run base --builds builds --test-user pawperf --trace --batches 1 --iterations 2
# After pilot inspection, five unchanged-build calibration batches:
python3 bench.py run base --builds builds --test-user pawperf
# Later, five alternating A/B pairs:
python3 bench.py run base --against candidate --builds builds --test-user pawperf
# Read-only comparison of the actual printed directories:
python3 bench.py compare /path/to/calibration /path/to/paired-session
```

`--scene` is `switch` (default), `ops`, `idle`, `overview-off`, or `overview-on`. Eight static
fixture windows are split equally between two workspaces. Config is explicit: columns, AX
movement, fixed animations, no hooks/bindings/updater, no mouse warping, stage overview.
The driver warms both workspace directions before opening the recorder window. Workspace
geometry is checked in both directions; the fixture independently checks final real frames,
minimization and native foreground/key focus. Repeat important findings with fixed real apps
before generalizing beyond this fixture.

Defaults: 10 round trips/open-close cycles, 2-second spacing, 3-second final drain, 120-second
idle scene and 5 batches/pairs. `--windows`, `--iterations`, `--pace`, `--settle`, `--duration`,
`--batches` and `--trace` must match calibration and comparison. Use one display, fixed scaling,
refresh/appearance and power settings. Do not use, lock or compile on the desktop during a
scene. Sleep is inhibited while recording; a screen saver may still interfere.

## Results and profiling

Sessions are private under `~/Library/Logs/paw-bench/<run-id>/`. Each batch retains config,
pre/post identity and trust, fixture environment, logs, raw `workload.json` samples and raw
`measurement.json` intervals/counters/resources, plus `result.json`. Sessions retain their
signature, artifact hashes, batch identities, failure evidence and readable `summary.md`.

The recorder measures command entry→return, actual queued AX sends, queued focus (including
skipped requests), animation lifetime and thumbnail capture. Animation lifetime reflects its
configured duration and is a trace marker, not a speed score. Whole-scene CPU is actual
user+system process time, including final drain. Memory is **process-lifetime peak RSS**,
not interval footprint or allocation churn. Recording is bounded/in-memory; disk output occurs
after the window. Missing/failed images, failed AX writes, wrong command/sample counts,
incomplete work, dropped records, non-nominal start/end thermal readings, changed environment
or bad geometry invalidate a batch. Work counts remain visible; fewer writes can be valid,
but explain changed work and verify preserved outcomes.

`--trace` attaches Time Profiler + signposts to the verified PID, waits for the documented
start notification, saves raw `profile.trace`, and explicitly produces
`profile-symbolicated.trace` with the selected app's dSYM. No Spotlight symbol discovery is
assumed. Inspect known symbols and spans manually. Profiling overhead is part of that workload:
use a separate calibration for traced runs, and inspect plain/instrumented pilots before
trusting tiny deltas. A successful symbolication command cannot prove every frame resolves.

Comparison rereads raw data, checks summaries, workload/identity signatures, safe unique batch
paths and pairing. It requires five calibration batches and five pairs. The primary metric
is whole-scene CPU for switch/ops, CPU per second for idle, opening command median for
overview-off, and fresh capture median for overview-on. A result is improved/regressed only
when every pair agrees and the median paired difference exceeds the full calibration range.
A zero range or ambiguous result is inconclusive. This is a conservative decision aid,
not a confidence interval or approval of every resource/behavior trade-off.

## Before taking the draft out of draft

Run `just bench check` later: pure Swift checks and Python controller checks use synthetic
records/mocked processes and launch no PAW/fixture/desktop benchmark. This command is prepared
in CI but has not been executed during preparation. Do not confuse compilation with passing tests.

Then explicitly run the plain and instrumented pilots. Confirm signing/trust and environment
delivery; warm-up outside measurement markers; readable symbols/signposts; exact window
distribution, both workspace directions and native final focus; separate overview open/close
metrics and eight fresh images on each opening. Check normal exit, Ctrl-C, Terminal close,
startup failure and the independent hung-app recovery with disposable processes. These checks
are still outstanding. Only then collect calibration and start evidence-backed optimization.

Ctrl-C/SIGTERM/SIGHUP enter cleanup. The candidate is found by its owned executable path even
without a socket; fixtures and trace handles belong to the session. SIGKILL/power loss cannot
clean up the controlled session: stop its candidate/fixture manually before retrying. Logs and
incomplete sessions remain for inspection; comparison refuses them.
