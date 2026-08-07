## Summary

Describe the problem and the resulting behavior.

## Validation

- [ ] `swift package resolve` leaves `Package.resolved` unchanged
- [ ] `swift test`
- [ ] `swift build -c release`
- [ ] `ruby Scripts/check-localizations.rb`
- [ ] Manual macOS verification where required
- [ ] `git diff --check`

## User experience and performance

- [ ] New recurring work is bounded, non-overlapping, and stops while hidden
- [ ] UI changes were checked with Reduce Motion and animations disabled
- [ ] UI changes were checked in English and Simplified Chinese
- [ ] Performance claims include the workload, build type, and measurement method

## Safety and compatibility

- [ ] No personal Codex data, exported profiles, logs, credentials, signing
      files, or absolute user paths are included.
- [ ] Local listeners remain loopback-only.
- [ ] Configuration writes remain merged, atomic, and backed up.
- [ ] English and Chinese documentation are updated together.
- [ ] `CHANGELOG.md` and third-party notices reflect user-facing and dependency changes.
