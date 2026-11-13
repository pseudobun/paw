# Performance

What paw costs, measured, and how to measure it again. The numbers below were measured on
2026-11-11 on a Mac mini (Apple silicon, macOS 27.2) over Screen Sharing (1648×1020). They compare
`main` before and after the main-thread work in [#52](https://github.com/pseudobun/paw/pull/52).

The dev build ran with 6 TextEdit and Finder windows tiled (bsp) on workspace 1 and 6 on
workspace 2. Windows moved over Accessibility; the Dock helper was not loaded.

## How to measure

```sh
just dev                  # build and run paw Dev
# put a few windows on workspaces 1 and 2 (TextEdit documents are fine)
just bench switch 200     # workspace 1 ↔ 2
just bench ops 200        # focus, swap, resize, layout changes, query
just bench hung TextEdit  # the same commands with TextEdit stopped (SIGSTOP)
```

`scripts/bench/wmbench.swift` talks to paw over its socket.

- **Round trip:** elapsed time from sending a command until its reply, including IPC and
  scheduling. It excludes asynchronous follow-up work and is not a measurement of main-thread CPU.
- **Geometry (current driver):** time until WindowServer frames match PAW's intended frames
  within 4 points, including the windows meant to be parked. This checks positions and sizes,
  not presented pixels. A timeout invalidates the batch.
- **Hung:** each command's round trip while one app with windows on both workspaces is stopped.
  This is the worst case of an app that stops answering Accessibility (beachballing, busy with
  indexing).

The current driver alternates operations and rejects no-ops, missing windows, bad replies and
timeouts. `ops` establishes columns on workspace 1 and leaves it in columns. `hung` has a separate
resume watchdog, scoped to the current user's process identities. Quick commands still use
the already-running dev app and desktop; they do not verify a candidate artifact or constitute
a controlled A/B comparison. See [the runbook](docs/benchmarking.md) for archived builds, fixtures,
CPU/idle/overview measurements, saved comparisons and optional Instruments traces.

Other tools used for this report:

| Measurement | Tool |
|---|---|
| Memory | `footprint <pid>`, `heap`; `leaks` needs a build signed with `get-task-allow` |
| Where the main thread spends its time | `sample <pid> 10`, symbolicated with `atos` against `.build/release/paw` |
| Idle CPU | `top -l 30 -pid <pid> -stats cpu` |

## Results

These are the original manually collected results from the earlier workload. The current
driver changes warm-up, pacing, geometry validation and operation ordering, and computes a true
median. Collect a new unchanged-build calibration before comparing its results; these tables
are historical evidence, not a baseline for the new driver. No new measurements are claimed.

### At rest

| | |
|---|---|
| Footprint after launch | 14–16 MB |
| Footprint after 200 switches | about 23 MB, then flat |
| Idle CPU | about 0.1 % |
| Leaks (`leaks`, after 10 000 IPC requests, 200 switches, 650 commands) | none |
| Launch → socket answers | 190–260 ms |
| IPC `status` | 0.1 ms |
| IPC `query`, 15 windows | 0.3–0.8 ms |
| 10 000 requests from 20 concurrent clients | 5.7 s, no errors |

### Window management

p50 / p99, milliseconds:

| | before | after |
|---|---|---|
| Workspace switch, round trip | 9.1 / 38.7 | **5.6 / 17.7** |
| Workspace switch, all on screen | 48.5 / 552 | **41.1 / 544** |
| CPU for 200 switches | 4.86 s | **3.21 s** |
| Layout change | 100 / 212 | **3.2 / 31.6** |
| Resize | 4.0 / 82 | **0.12 / 9.1** |
| Swap | 0.10 / 32.7 | **0.06 / 1.2** |
| Focus | 0.11 / 1.9 | 0.21 / 1.2 |

On the switch "all on screen" p99: an app occasionally takes about half a second to move its
window, with or without these changes. That latency is the app's, not paw's.

### A hung app

How long one command held paw's main thread, in milliseconds, with TextEdit stopped:

| Command | before | after |
|---|---|---|
| `layout columns` | 9 542 | **12.7** |
| `layout bsp` | 6 127 | **0.5** |
| `swap west` | 94 | **0.2** |
| `focus east` | 65 | **0.6** |
| `workspace 2` / `workspace 1` | 9.4 / 1.7 | 4.6 / 27 |

Before, every hotkey, CLI call and indicator waited that long. After TextEdit resumes, its windows
land where the layout says: their real frames matched paw's, with 0 mismatches.

### Screen locked at launch

A paw started while the screen was locked (a login item, a restart over SSH) used to manage 1 of
16 windows after unlocking. Now it manages all 15, each on the workspace it was on.

## What changed

1. **The main thread never waits on an app.**
   - Every window move goes to that app's own queue (`AXQueue`): commands, AX events, animation
     frames, seam drags. The queue keeps only each window's newest move.
   - A move made outside a command waits at most 50 ms for a send already under way, then queues
     behind it.
   - An app whose Accessibility calls time out (`AXHealth`) is skipped on the main thread for
     2 s, then 4, 8, … up to 30 s; an answer clears it. Its own queue keeps talking to it.
2. **Event taps on their own thread** (`EventTapThread`).
   - Key presses, scrolls and gestures are answered there; only the commands go to the main
     thread.
   - The mouse tap listens only for what the config uses.
   - A held key's repeats are dropped while one is still waiting to run.
3. **Less redrawing.**
   - Seam panels are reused across workspace switches. Making new ones took 22 % of the main
     thread's time while switching.
   - `updateIndicators()` runs at most once per run-loop turn. A single focus change used to run
     it three times, and it took 33 % of the main thread's time while switching.
   - Stacks, placeholders and edge markers are redrawn only when they changed.
4. **Unlock.** paw adopts the windows it couldn't see while the screen was locked.
5. **Background work.**
   - Closed windows are found by asking about paw's windows only: 0.2 ms instead of about 5 ms
     every 2 s.
   - An app's windows are removed with one layout.
   - Icon images are cached in a few sizes.
   - Overview captures are capped at 480 pt and cancelled on close.
6. **Smaller things.**
   - Size retries triggered by title changes back off.
   - A stale focus request is skipped.
   - Hover is checked once more after the pointer stops.
   - Event payloads are built only for subscribers.
   - Hooks start off the main thread.
   - `query` is encoded on the IPC thread.

## Release build at rest

Measured on 2026-11-12 on olympus: Mac mini, Apple M4 Pro, 24 GB, macOS 27.2, one display
(3320 × 2040, Screen Sharing). The installed release builds from the beta casks ran together:
paw 0.1.0-beta.21, hop 0.1.0-beta.13 and tip 0.1.0-beta.1.

Idle counters come from `proc_pid_rusage` (CPU time, `ri_pkg_idle_wkups` + `ri_interrupt_wkups`,
`ri_phys_footprint`) over 120 s with nobody at the keyboard. CLI round trips are the median and
p90 of 50 runs after 10 warm-up runs, process start included; starting `/usr/bin/true` costs
1.4 ms on this machine.

| | |
|---|---|
| Idle CPU | 0.02 % |
| Wakeups | 5.5 per 10 s |
| Footprint | 15.7 MB (peak 15.9 MB) |
| Threads | 5 |
| App bundle / binary | 8.0 MB / 4.3 MB |
| `paw status` | 8.9 ms p50, 11.5 ms p90 |
| `paw query --json` (7 workspaces) | 8.5 ms p50, 9.4 ms p90 |

paw managed 7 workspaces with one window during the run, so these are the floor. The window
management numbers above need `just bench` against paw Dev with windows on two workspaces.

## Liquid Glass

Measured on 2026-11-13 on olympus (Mac mini, Apple M4 Pro, macOS 27.2): the release-configuration
dev build (`PAW_DEV=1 scripts/bundle.sh`), `appearance.glass` on and off, paw restarted between
runs, on and off interleaved. The screen was locked and paw managed no windows, so the panels
shown were the workspace HUD and an edge marker.

| | glass on | glass off |
|---|---|---|
| Idle CPU (120 s) | 0.011 % | 0.009 % |
| Wakeups | 4.9 per 10 s | 5.3 per 10 s |
| Footprint at rest | 16.6 MB | 14.2 MB |
| paw CPU per workspace switch (HUD shown), median of 12 × 200 | 4.0 ms | 4.3 ms |
| `paw workspace` round trip, CLI start included, median of 12 × 200 | 14.0 ms | 15.0 ms |

- The switch numbers spread by ±0.6 ms from run to run with either setting: no difference
  shows. The main thread's time in a switch goes to ordering the HUD in
  (`SLSWindowIsOrderedIn`), the same with and without glass.
- Glass costs about 2.5 MB once, as soon as the first glass island shows (AppKit's glass
  machinery: dirty `__DATA` and malloc). It doesn't grow with more islands or switches.
- The window server draws the glass. paw sets its shape, tint and light or dark only when they
  change and draws no frames for it; the islands' content rises into place with one Core
  Animation group (240 ms, skipped with Reduce Motion).

To measure again: `appearance.glass` in a copy of the config, `PAW_CONFIG=<copy>` for the dev
build, and the `proc_pid_rusage` counters above around 100 × `paw workspace 2; paw workspace 1`.

## Known costs

- Reading from an app (titles, frames, its windows) is still synchronous. A slow app costs up
  to one 0.5 s timeout before `AXHealth` skips it.
- With Accessibility, a switch is done when the slowest app has moved its windows. The Dock
  helper (README, "Faster workspace switching") moves them all in one frame.
- `workspaceOf(id)` walks every workspace's tree. That is fine at tens of windows; an index
  would help at hundreds.

`swift test` covers the queue, the slow-app backoff, key repeats, the tap thread, the mouse mask,
seam reuse and the caches (`Tests/PawTests/MainThreadTests.swift`, `EventAndRedrawTests.swift`).
Manual checks are in [TESTING.md](TESTING.md), under "A hung app".
