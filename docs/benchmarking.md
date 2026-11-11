# Measuring PAW changes

One entrypoint, `just bench`: the Swift driver owns workloads, and the stdlib Python controller
owns artifacts, controlled sessions, captures and comparisons. Normal builds compile the
in-app recorder out. This prepares measurement infrastructure, not an optimization.

**Status:** see "Validation status" at the end; it lists what has run on real hardware and what
is still outstanding. Do not treat a verdict as trustworthy before those items pass.

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

## One-time setup

Use full Xcode/Instruments and Python 3.9+. Benchmark builds are a separate app, **paw Bench**
(`com.pseudobun.paw.bench.dev`): its own data, cache, defaults, socket and privacy grants. Your
daily paw Dev/release PAW, their config, state and grants are never replaced; status bars talking
to `paw`/`paw-dev` never reach it.

```sh
just bench-cert                          # once: "paw Bench Signing" in its own keychain
just bench prepare base                  # compile/archive only; never launches anything
just bench grant base --user "$(id -un)" # once: opens paw Bench managing no window
```

`bench-cert` creates `~/Library/Keychains/paw-bench.keychain-db` with a random password in a
0600 file beside it. It is on the keychain search list only while `prepare` signs (codesign finds
identities nowhere else), so builds never prompt and `just dev` keeps its own signing. Anyone who
can run code as you can sign with it, so it is as strong as an "Always Allow" codesign key; remove
it, and the grants, when done:

```sh
security delete-keychain ~/Library/Keychains/paw-bench.keychain-db
rm ~/Library/Keychains/paw-bench.keychain-db.password
tccutil reset Accessibility com.pseudobun.paw.bench.dev
tccutil reset ScreenCapture com.pseudobun.paw.bench.dev
```

`grant` opens paw Bench's Settings → General with a config that ignores every window. Request
Accessibility (and Screen Recording for `overview-on`) and enable paw Bench in System Settings;
it waits up to 15 minutes. The grant follows the certificate and bundle ID, so later builds keep
it. The runner never changes privacy settings itself.

Artifacts live in `build.noindex/bench/builds/<label>/`; labels cannot be reused. Each contains
the signed paw Bench app, dSYM, fixture app, workload executable, source hashes, tracked dirty
patch, untracked build-input source archive, UUIDs, compiler/environment/signing metadata and
build logs. Source capture is restricted to the app/resources, package/version files, bundler,
workload controller/driver and fixture. Changes to sources or revision while building fail
preparation. Both A/B sides use the **base artifact's exact driver and fixture binaries**; their
source and compiler versions must agree with the candidate. Do not edit the controller between
calibration and comparison: `run` refuses artifacts archived with another controller.

## Controlled sessions (current user)

`run` is live and opts in by naming your login (`--user`). It refuses root, another logged-in
user, a console owned by someone else and an active `com.pseudobun.paw` launchd agent. Then it:

1. records the running PAW apps (CLI processes such as a status bar's `paw subscribe` are not
   apps) and starts an independent restorer in its own session, attached by an EOF pipe;
2. quits those apps with SIGTERM, which puts their hidden windows back;
3. per batch, replaces only paw Bench's app/data/cache, launches it with an explicit config that
   manages only the fixture's windows (every other app, including T3 Code, is ignored), starts the
   fixture, runs the workload and verifies the result;
4. when the session ends, fails, gets Ctrl-C or SIGTERM, its Terminal closes (SIGHUP) or the
   controller is SIGKILLed, the restorer quits paw Bench (SIGKILL if it hangs) and reopens the
   apps from step 1 that are not running. It never starts two window managers.

The fixture exits with its controller's pipe. Power loss or killing the restorer too can still
leave PAW quit: reopen it yourself. Don't use, lock or compile on the desktop during a session.

```sh
# Pilots: one plain trace, then one instrumented trace; inspect them in Instruments:
just bench run plain-base --user "$(id -un)" --trace --batches 1 --iterations 2
just bench run base --user "$(id -un)" --trace --batches 1 --iterations 2
# Five unchanged-build calibration batches:
just bench run base --user "$(id -un)"
# A/A negative control, then a real A/B, each five alternating pairs:
just bench run base --against base --user "$(id -un)"
just bench run base --against candidate --user "$(id -un)"
# Read-only comparison of the printed directories:
just bench compare /path/to/calibration /path/to/paired-session
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
refresh/appearance and AC power. Sleep is inhibited while recording; a screen saver may still
interfere. Each batch records the load average before it starts, to explain outliers.

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

Ctrl-C/SIGTERM/SIGHUP enter cleanup; restoration runs in the independent restorer either way.
Logs and incomplete sessions remain for inspection; comparison refuses them.

## Validation status

`just bench check` (pure Swift checks and Python controller checks with synthetic records and
mocked processes) runs in CI. Checked on real hardware with disposable processes: the hung
diagnostic's watchdog resumes a stopped target after normal exit, SIGINT, SIGHUP and controller
SIGKILL; a controlled session restores the daily paw Dev (and stops paw Bench) after a startup
failure, SIGINT, SIGHUP and controller SIGKILL. Pilots, calibration and A/A/A/B results are
summarized in the pull request that introduced this harness.
