# Contributing to TourBox Micro

TourBox Micro welcomes focused contributions for additional TourBox hardware,
TourBox Console compatibility, Codex desktop changes, accessibility, tests,
documentation, and native macOS polish.

## Before opening a change

- Search existing issues and pull requests.
- Keep the change focused on one problem.
- For a new hardware model or Console version, describe the exact tested setup.
- Never commit personal Codex databases, rollout files, hooks, keybindings,
  exported TourBox profiles, device logs, signing identities, certificates, or
  absolute user paths.
- Do not add third-party code or binary assets unless their license permits
  redistribution and their notice is included.

## Development setup

Requirements:

- macOS 14 or later
- Xcode or a Swift 6 toolchain

```sh
git clone https://github.com/MJYKIM99/tourbox-micro.git
cd tourbox-micro
swift test
```

The core test suite does not require TourBox hardware. End-to-end input,
Accessibility, TourBox Console, HUD, and Codex deep-link changes require manual
verification on macOS.

## Making a change

1. Create a topic branch from `main`.
2. Add or update tests for core behavior.
3. Keep platform-specific UI and system integration in `TourBoxMicro`; keep
   deterministic protocol, routing, and state logic in `TourBoxCore`.
4. Run `swift test`.
5. Verify that `git diff --check` is clean.
6. Update English and Chinese documentation together when user-facing behavior
   changes.

## Pull request checklist

- [ ] The change is focused and explained.
- [ ] `swift test` passes.
- [ ] No local paths, personal data, credentials, or generated build products
      are included.
- [ ] New dependencies have a clear need, pinned version, compatible license,
      and updated `THIRD_PARTY_NOTICES.md`.
- [ ] Runtime listeners remain loopback-only.
- [ ] Configuration writes remain merge-based, atomic, and backed up.
- [ ] UI changes respect Reduce Motion and macOS accessibility settings.
- [ ] English and Chinese docs agree.

## Reporting bugs

Use the bug report form and include sanitized diagnostics. Follow
[SECURITY.md](SECURITY.md) instead when a report could expose data or enable
unintended input or code execution.
