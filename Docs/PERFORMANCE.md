# Performance Notes

TourBox Micro is a long-running menu-bar application, so its performance target
is low steady-state work rather than maximum throughput. The app should do work
when TourBox input, Codex lifecycle state, or visible UI state changes and stay
quiet otherwise.

## v0.8.0 runtime design

- Codex thread queries use the SQLite C API with a bounded `LIMIT` instead of
  launching a `sqlite3` subprocess and decoding an unbounded result.
- Database and rollout-file work runs at utility priority outside the main
  actor.
- A five-second thread refresh uses timer tolerance and cannot overlap itself.
- Rollout reconciliation runs at most once every fifteen seconds after launch,
  scans changed files once, and shares that result between lifecycle and
  presentation readers.
- Slot resolution and HUD rendering are skipped when their inputs have not
  changed.
- The HUD is created lazily and its AppKit and SwiftUI trees are released when
  hidden. Settings diagnostics update only while Settings is open.
- The six compact lights use one native visual-effect plane with six rounded
  mask regions. Their colors are static state indicators; only bounded state
  transitions and direct interaction animate.

## Manual diagnostic sample

The v0.8.0 investigation used a Release build on this environment:

- MacBook Pro with Apple M5 Pro and 24 GB memory
- macOS 26.5.1
- Six-light HUD visible with multiple assigned Codex tasks
- Application animation preference enabled
- Fifteen process samples taken one second apart after launch settled

Observed app CPU averages during the investigation:

| Rendering path | Average app CPU |
|---|---:|
| Per-light material and continuous SwiftUI shimmer | 14.64% |
| Shared masked glass with a shared SwiftUI timeline | 7.20% |
| Transform-only continuous SwiftUI animation | 6.08% |
| v0.8.0 masked glass with static state illumination | 1.21% |

These measurements identified continuous animation as the dominant visible-HUD
cost. They are diagnostic observations, not a controlled cross-version or
cross-device benchmark: the live task mix changed during the investigation,
and display refresh rate, macOS, hardware, and background load affect results.

## Reproducing a spot check

Build and install a Release application, make the HUD visible, and let startup
settle before sampling:

```sh
./Scripts/build-app.sh --install
open "/Applications/TourBox Micro.app"

PID=$(pgrep -x TourBoxMicro)
for sample in {1..15}; do
  ps -p "$PID" -o %cpu=,rss=
  sleep 1
done
```

Record the task-state mix, animation preference, display refresh rate, hardware,
macOS version, build configuration, and sample duration with any result. Compare
like-for-like workloads and inspect CPU, wakeups, memory, and Energy Log before
claiming a regression or improvement.

## Performance review checklist

- No repeating animation or timer should survive while its UI is hidden.
- Polling must be bounded, tolerant, non-overlapping, and off the main actor.
- File and database reads should fetch only data required for the visible state.
- Published model values and AppKit updates should be equality-guarded.
- New visual effects must be profiled with several active task lights, not only
  an empty or idle HUD.
