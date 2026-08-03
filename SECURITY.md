# Security Policy

## Supported versions

TourBox Micro is currently a public beta. Security fixes are applied to the
latest commit on `main` and the newest published release. Older source snapshots
are not maintained separately.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose local Codex
content, execute unintended input, bypass the loopback boundary, or modify user
configuration unexpectedly.

Use GitHub's private vulnerability reporting:

<https://github.com/MJYKIM99/tourbox-micro/security/advisories/new>

Include the affected version, macOS version, reproduction steps, expected and
actual behavior, and the smallest possible sanitized log. Do not attach real
Codex databases, rollout files, prompts, responses, signing certificates, or
TourBox Console databases.

## Security boundaries

- Both local services must remain bound to `127.0.0.1`.
- Configuration changes must merge with existing JSON and create a backup
  before writing.
- Keyboard and scroll synthesis requires explicit macOS Accessibility consent.
- Deep links may open an existing Codex task but must not execute shell input.
- Preset generation must treat its source as read-only and write to a separate
  output path.
- No secrets, personal databases, exported profiles, signing keys, or device
  logs belong in the repository.

## Public bug reports

Non-sensitive reliability and UI bugs are welcome in GitHub Issues. Run
`TourBoxMicro --doctor` when useful, and review its output before sharing it.
