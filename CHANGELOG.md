# Changelog

All notable changes to TourBox Micro are documented in this file. The project
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.9.0] - 2026-08-07

### Added

- Added complete English and Simplified Chinese localization with 247 catalog
  keys and a CI check for locale parity, format placeholders, missing UI keys,
  and hard-coded Han-character regressions.
- Added a first-run Setup Assistant covering Codex, lifecycle Hooks,
  Accessibility, the TourBox preset, and completion; it can be rerun from the
  menu bar.
- Added authenticated lifecycle hooks using a per-install 256-bit local token
  stored with owner-only permissions.

### Changed

- Discover the newest versioned Codex `state_N.sqlite` database instead of
  assuming `state_5.sqlite`, and report incompatible schemas without exposing
  local paths.
- Require a valid TourBox protocol event before a new TCP candidate can replace
  an active hardware connection.
- Updated the app metadata to version 0.9.0 (Build 19), with English as the
  development region and explicit English and Simplified Chinese locales.

### Security

- Bounded lifecycle HTTP requests to 8 KiB of headers and 64 KiB of JSON, with
  content-type validation, a three-second timeout, and an eight-connection cap.

### Fixed

- Added atomic runtime status maintenance: semantically empty idle rows outside
  the visible thread window are removed, stale orphaned active rows are deleted,
  and remaining day-old running or input states become idle without a restart.
- Invalidated the last database fingerprint after a failed Codex read so an
  unchanged database is actively retried instead of being mistaken for a
  recovered no-op refresh.
- Added privacy-preserving SQLite operation/error codes and outage duration to
  lifecycle logs without recording database paths, task titles, or content.

## [0.8.1] - 2026-08-07

### Added

- Privacy-preserving lifecycle diagnostics for deferred, canceled, and
  committed permission signals, plus Codex database failure and recovery.

### Fixed

- Debounced permission hooks for 750 milliseconds and canceled them when a
  matching tool-use or lifecycle event proves that Codex continued running.
- Dismissed an existing “action required” card as soon as its task returns to
  running, completes, disappears, or otherwise changes state.
- Cleared transient Codex database errors after the next successful refresh
  instead of leaving a recovered failure permanently visible in the HUD.
- Expired day-old running and input-request rows during startup so abandoned
  task state cannot return as current attention.
- Matched deferred hook events by both thread ID and working directory when one
  of the later hook payloads omits an identifier.
- Bounded cached rollout summaries to the current recent-thread window instead
  of retaining text for threads that can no longer appear in the HUD.

### Performance

- Added a main-database and WAL change fingerprint so the fallback poll performs
  a full Codex SQLite query only after an actual database change.
- Added adaptive thread discovery: no-hook and stale-hook installations retain
  the previous five-second response, while healthy hooks use immediate unknown-
  thread discovery and a tolerant fifteen-second fallback.
- Included device and inode identity in database and rollout fingerprints, and
  followed symbolic-link targets so atomic file replacement cannot be missed.

## [0.8.0] - 2026-08-06

### Added

- Native frosted-glass surfaces for the settings window, detailed HUD, and six
  compact status lights.
- Focused repository tests for native Codex thread queries and bounded activity
  persistence.

### Changed

- Moved Codex database queries and rollout parsing to utility-priority
  background work, with coalesced refreshes and timer tolerance.
- Reconciled lifecycle and presentation state from one bounded rollout scan and
  rendered only when the resulting HUD state changes.
- Created the HUD lazily and released its windows and SwiftUI tree while hidden.
- Updated diagnostics only while Settings is open and released the settings
  model when its window closes.
- Replaced continuous light animations with vivid static state illumination;
  completion, error, and hover feedback remain event-driven.

### Fixed

- Removed the full-width rectangular glass plate behind the six-light HUD while
  preserving an independent native glass surface for every light.
- Restored blue, green, amber, and red state colors that a paused shimmer layer
  could incorrectly cover with white.
- Prevented overlapping thread refreshes, duplicate rollout reads, redundant
  SwiftUI publication, and unnecessary hidden-window rendering.
- Preserved stable HUD sizing and positioning across style changes and relaunches.

### Performance

- Replaced shell-based SQLite reads with the native SQLite API and bounded the
  visible-thread query at the database layer.
- Removed the continuously refreshing SwiftUI-Shimmer dependency.
- Reduced thread refresh frequency from two to five seconds and rollout parsing
  to at most once every fifteen seconds outside the initial reconciliation.

## [0.7.2] - 2026-08-03

### Added

- Native macOS menu-bar app and settings window.
- TourBox Elite Max/MSP event decoding with press, release, and rotation input.
- Configurable base controls and a Tour modifier layer.
- Six stable Codex task slots with priority, recent, and pinned modes.
- Glass-light and detailed-list HUD styles with native hover details.
- Codex deep-link navigation, lifecycle hooks, and local diagnostics.
- SQLite lifecycle persistence and bounded rollout-tail recovery.
- Push-to-talk, frontmost-app copy and paste, screenshot, scrolling, reasoning
  adjustment, search, approval, and review actions.
- Safe merge-and-backup installation for Codex hooks and keybindings.
- Corrected TourBox preset generation for C1 and C2 Max/MSP bindings.
- Swift Testing coverage for protocol, routing, configuration, persistence,
  rollout, display text, slot ordering, and transition behavior.

[Unreleased]: https://github.com/MJYKIM99/tourbox-micro/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/MJYKIM99/tourbox-micro/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/MJYKIM99/tourbox-micro/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/MJYKIM99/tourbox-micro/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/MJYKIM99/tourbox-micro/releases/tag/v0.7.2
