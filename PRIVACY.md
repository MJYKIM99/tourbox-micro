# Privacy

TourBox Micro is designed as a local macOS utility. Its runtime integrations
stay on the user's Mac, and the app does not include analytics, advertising,
telemetry, account creation, or a remote backend.

## Data TourBox Micro reads

TourBox Micro may read the following local data to provide its features:

- TourBox Max/MSP input sent to `127.0.0.1:50500` by TourBox Console.
- Codex lifecycle hook requests sent to `127.0.0.1:50501`.
- `~/.codex/state_5.sqlite` for task identity, title, project directory,
  recency, pinned state, and rollout-file location.
- A bounded tail of referenced Codex rollout JSONL files to recover the latest
  visible assistant update and infer whether interrupted work is still active.
- `~/.codex/hooks.json` and `~/.codex/keybindings.json` when installing or
  diagnosing the local integration.
- macOS Accessibility trust status and the presence of the Codex app.

TourBox Micro does not read or store clipboard contents. Copy and paste actions
only synthesize the corresponding keyboard shortcut in the frontmost app.

## Data TourBox Micro stores

The app stores lifecycle metadata in:

```text
~/Library/Application Support/TourBox Micro/status.sqlite3
```

That SQLite database contains:

- Codex task ID and working directory
- lifecycle state and last update time
- whether a completed state has been acknowledged

The latest visible assistant update is kept in memory and is not written to
the TourBox Micro database. Full prompts, full responses, reasoning content,
clipboard content, and raw TourBox input are not stored by TourBox Micro.

HUD settings, control mappings, and slot preferences are stored with macOS
`UserDefaults` under the app's bundle identifier, `com.yi.tourboxmicro`.

## Network behavior

At runtime, TourBox Micro listens only on the loopback interface:

- TCP `127.0.0.1:50500` for TourBox Console Max/MSP input
- HTTP `127.0.0.1:50501` for Codex lifecycle hooks

The app does not upload Codex data or TourBox input. Building from source may
contact GitHub to download the Swift package dependencies declared in
`Package.swift`.

## User control

- TourBox Micro can be used without launch-at-login.
- HUD details, status notifications, animation, mappings, and slot ordering are
  configurable in Settings.
- The Codex installer makes timestamped backups before changing hook or
  keybinding files.
- Accessibility permission can be revoked in macOS System Settings.
- Quitting or removing the app stops both loopback listeners.

## Questions

For a privacy question or suspected data-handling bug, open a GitHub issue that
contains no personal Codex content. Security-sensitive reports should follow
[SECURITY.md](SECURITY.md).
