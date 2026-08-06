# Changelog

All notable changes to TourBox Micro are documented in this file. The project
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/MJYKIM99/tourbox-micro/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/MJYKIM99/tourbox-micro/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/MJYKIM99/tourbox-micro/releases/tag/v0.7.2
