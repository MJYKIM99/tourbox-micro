# Codex compatibility audit — 2026-09-24

Status: investigation complete. Resolved in 0.10.0; see
[Resolutions](#resolutions-0100) at the end of this document.

This audit checks whether the Codex desktop app changed in ways that require
TourBox Micro to be updated. The project's last release was 0.9.0 (Build 19) on
2026-08-07.

## Environment at audit time

| Item | Value |
|---|---|
| Codex desktop app | `ChatGPT.app` 26.917.62051 (build 10789), updated 2026-09-23 |
| Codex CLI | `codex-cli 0.154.0` |
| Session `cli_version` seen in rollouts | `0.155.0-alpha.16.3` (`originator: Codex Desktop`) |
| macOS | 27.0 (26A428) |
| Xcode / Swift | 27.0 (27A266a) / Swift 6.4 |
| Project revision | `9a1e858` on `codex/localization-onboarding-hardening` (5 commits ahead of local `main`) |
| Installed app | `/Applications/TourBox Micro.app`, 2026-08-07 (not running; last local state write 2026-08-12) |

## Verification results

| Check | Method | Result |
|---|---|---|
| Build and unit tests | `swift test` | **55/55 pass** on Swift 6.4 / Xcode 27 |
| Integration diagnostics | `swift run -c release TourBoxMicro --doctor` | **All green** (app found, DB found, hooks installed, F13-F15 installed, F18 installed, F16/F17 assigned, Accessibility granted) |

## Integration contracts still intact

1. **Deep links** — `com.openai.codex` still owns the `codex` URL scheme, and
   `codex://threads/` is still a valid route.
2. **Keybinding command names** — `composer.toggleFastMode`,
   `composer.togglePlanMode`, `forkThread`,
   `composer.increaseReasoningEffort`, and
   `composer.decreaseReasoningEffort` all still exist, and the app still reads
   `~/.codex/keybindings.json`.
3. **Hook events** — `UserPromptSubmit`, `PermissionRequest`, `PostToolUse`,
   and `Stop` are still supported. Omitting `matcher` is explicitly supported
   ("omit `matcher` entirely to match every occurrence").
4. **Hook input fields** — hooks still receive `session_id` and `cwd`, which is
   exactly what `HookClassifier` matches on.
5. **State database** — `threads` still contains every column the repository
   queries (`id, title, cwd, preview, recency_at_ms, is_pinned, rollout_path,
   archived, source`). The repository query returns 1035 visible rows out of
   1953 total threads.
6. **Rollout files** — still emit `task_started` / `task_complete` (with
   `last_agent_message`) and `response_item` -> `message` -> `role: "assistant"`
   -> `output_text`. Both `RolloutStateReconciler` and
   `RolloutPresentationReader` still parse them.
7. **Hook trust** — the app already instructs users to "review and trust the
   hooks when prompted", matching Codex's hash-based trust gate.

**Conclusion:** the project is not broken by the Codex update. A rewrite or
emergency patch is not required.

## Confirmed defects (Codex shortcut drift)

### 1. "Search all chats" sends the wrong key - real bug

- `CodexController.perform(.searchChats)` sends `Cmd+G`.
- In current Codex, `Cmd+G` is **Find next match**. The desktop app's
  `searchChats` command has **no default keybinding** (only the browser build
  defaults to `Cmd+K`), and the official docs list "Search chats ... Not
  assigned by default".
- Result: Dial press does not open chat search; it can trigger find-next.
- Fix: install a binding for the app's `searchChats` command in
  `keybindings.json` (e.g. `F18`) and send that key instead of `Cmd+G`.

### 2. "Jump to latest message" has no Codex command to bind

- `CodexController.perform(.jumpToLatest)` sends `Cmd+Down`.
- Codex exposes no "jump to latest" or "scroll to bottom" command to bind: the
  app's command table has neither, and the conversation only renders a
  scroll-to-bottom button. Chromium's default `Cmd+Down` ("move to end of
  document") is the mechanism that actually reaches the end of the
  conversation.
- An accessibility fallback was investigated and rejected: the app is Electron,
  so the accessibility tree exposes `AXWebArea` and buttons but no `AXScrollBar`
  to drive, and the scroll-to-bottom button is localized and only present while
  scrolled up.
- Outcome: keep `Cmd+Down` and document the dependency rather than add fragile
  automation.

### 3. Screenshot action is a frontmost-app utility, not a Codex feature

- `.screenshot` sends `Shift+Cmd+2` to the frontmost app by design.
- Codex now has a first-class "Take an Appshot" (`Cmd+Cmd`) capability that
  could be offered separately or in addition.

## New Codex capabilities worth adopting

1. **Richer hooks.** Codex now supports `SessionStart`, `SessionEnd`,
   `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `PreToolUse`,
   and `Interrupt`. The project uses only four events.
   - `Stop` now carries `last_assistant_message`; HUD text could come straight
     from hooks instead of reading rollout files.
   - `SubagentStart` / `SubagentStop` would let the HUD track subagents, which
     matters because `multi_agent_v2` is enabled in this environment.
   - `SessionEnd` could drive local-state cleanup.
2. **Official hook documentation** at `developers.openai.com/codex/hooks.md`,
   including exact payload schemas - a stable contract to target.
3. **App-server protocol** (`codex app-server`, JSON-RPC 2.0 over stdio / ws /
   unix, `generate-json-schema`, `generate-ts`; plus `codex agents` and
   `codex remote-control`). This is the supported surface used by rich clients
   such as the VS Code extension and could replace SQLite + rollout scraping for
   thread lists and live status. It is currently marked experimental and "not
   supported for production workloads", so a hybrid approach (app-server with
   the existing database fallback) is the sensible path.
4. **Useful new default shortcuts**
   (`learn.chatgpt.com/docs/reference/commands.md`):
   - Next chat needing attention - `Opt+Cmd+A`
   - Open recent chat 1-6 - `Opt+Cmd+1-6`
   - Copy chat deep link - `Opt+Cmd+L`
   - Toggle bottom panel - `Cmd+J`
   - Toggle file tree - `Shift+Cmd+E`
   - Open browser tab - `Cmd+T`
   - Open side chat - `Opt+Cmd+S`
   - Start voice chat - `Ctrl+Shift+V` (dictation remains `Ctrl+Shift+D`, which
     the project uses correctly)
5. **`composer.cycleReasoningEffort`** - a single cycling command that could
   replace the manual F16/F17 record-once onboarding step.
6. **Multi-agent threads in the database** - subagent threads are stored with
   `source` as a JSON blob and `agent_nickname` / `agent_role` / `agent_path`.
   The repository query deliberately excludes them (`source NOT LIKE '{%'`), so
   subagents are invisible in the HUD. This is a product decision to revisit.

## Already-correct mappings (verified against the current keymap)

| Action | Key sent | Current Codex command | OK |
|---|---|---|---|
| Approve / send | `Return` | `approval.approve` | yes |
| Reject / cancel | `Esc` | `approval.decline` | yes |
| Toggle review panel | `Opt+Cmd+B` | `toggleSidePanel` | yes |
| Model picker | `Ctrl+Shift+M` | `composer.openModelPicker` | yes |
| Quick chat | `Opt+Cmd+N` | `quickChat` | yes |
| Find in chat | `Cmd+F` | `findInThread` | yes |
| Command menu | `Cmd+K` | command menu | yes |
| Search files | `Cmd+P` | search files | yes |
| New standalone chat | `Opt+Cmd+O` | `newProjectlessTask` | yes |
| Next / previous recent chat | `Ctrl+Tab` / `Ctrl+Shift+Tab` | `nextRecentThread` / `previousRecentThread` | yes |
| Navigate back / forward | `Cmd+[` / `Cmd+]` | `navigateBack` / `navigateForward` | yes |
| Toggle sidebar | `Cmd+B` | `toggleSidebar` | yes |
| Push-to-talk | `Ctrl+Shift+D` | `composer.startDictation` | yes |
| Reasoning | `F16` / `F17` | user-bound | yes |

## Recommended plan (as written at audit time)

The project does not need a rewrite, but it does deserve a small correctness
release plus an optional feature release:

- **0.9.1 (patch)** - fix the two shortcut defects (search-chats and
  jump-to-latest), and re-validate the documented compatibility matrix against
  the September Codex desktop build.
- **0.10.0 (optional)** - adopt `Stop.last_assistant_message` and
  `SubagentStart` / `SubagentStop` for hook-driven status, and evaluate the
  app-server protocol as a supported alternative to database scraping.
- Keep the hook command string byte-stable: any change invalidates Codex's
  hash-based hook trust and forces users to re-approve.

**Outcome:** both phases shipped together as **0.10.0**, since the fixes and
the hook-driven status work landed in the same change set. See
[Resolutions](#resolutions-0100) below.

## Resolutions (0.10.0)

| Finding | Resolution |
|---|---|
| Chat search sent `Cmd+G` | `ConfigurationInstaller` now owns `F18` for the app's `searchChats` command and the Dial press sends `F18`; installation replaces a stale `searchChats` binding. |
| Jump to latest had no command | Kept `Cmd+Down`; documented the webview "end of document" dependency after rejecting an accessibility fallback. |
| Screenshot was a frontmost-app utility | Left as a deliberate frontmost-app action; Codex's own Appshot is not part of the default mapping. |
| Richer hook events unused | Added `Interrupt` (returns the light to idle). |
| `Stop` carries `last_assistant_message` | Consumed: the HUD shows the final message as soon as the turn ends, using the same `AssistantMessageText` summarizer as the rollout reader. |
| New default shortcuts | Exposed four new selectable actions: next task needing attention (`Opt+Cmd+A`), copy task link (`Opt+Cmd+L`), toggle bottom panel (`Cmd+J`), open browser tab (`Cmd+T`). |
| App-server protocol | Not adopted in 0.10.0. It remains experimental and unsupported for production; revisit as a hybrid source with the existing database fallback. |
| Subagent threads excluded | Unchanged; still a product decision to revisit. |

Verification for 0.10.0: `swift test` (66 tests), `ruby Scripts/check-localizations.rb`
(251 keys), and `TourBoxMicro --doctor`.

## Method note

Findings come from the live install on this machine (app bundle command map,
`~/.codex/hooks.json`, `~/.codex/keybindings.json`, `~/.codex/state_5.sqlite`,
rollout JSONL) plus official documentation fetched from
`developers.openai.com/codex/hooks.md`, `developers.openai.com/codex/app-server.md`,
and `learn.chatgpt.com/docs/reference/commands.md`.
