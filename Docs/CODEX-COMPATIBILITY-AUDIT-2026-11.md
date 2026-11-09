# Codex Compatibility Audit — November 2026

Audit of **TourBox Micro** against the installed macOS **Codex** desktop app (`ChatGPT.app`, bundle identifier `com.openai.codex`) and **Codex CLI** as of November 2026.

## Tested Environment

| Component | Version / Build |
|---|---|
| Codex Desktop (`ChatGPT.app`) | `26.1103.60933` (`CFBundleVersion` `25894`, Electron `40.0.0`) |
| Codex CLI (`codex`) | `codex-cli 0.164.0` |
| Codex SQLite state store | `~/.codex/state_5.sqlite` |
| Codex command registry | `app.asar/.vite/build/early-bootstrap-339-cb7e73ca5a71df7c.js` (module `41251`, 189 commands) |
| Codex global hotkey runtime | `app.asar/.vite/build/early-bootstrap-815-e030c49be4b9c405.js` |

---

## 1. Shortcut Drift & Regressions Fixed in v0.11.0

Between the September 2026 (`26.917.62051`) and November 2026 (`26.1103.60933`) desktop releases, Codex introduced top-level tabs, replaced legacy in-app dictation and quick-chat commands with OS-global controllers, and expanded the command registry to 189 commands. Three default TourBox Micro actions and several command IDs required adaptation:

### 1.1 Recent Chat Cycling (`previousRecentThread` / `nextRecentThread`)

- **TourBox Micro v0.10 sent**: `⌃⇧Tab` and `⌃Tab` (`keyCode: 48` with `.maskControl` / `[.maskControl, .maskShift]`)
- **Codex Desktop (`26.1103.60933`) registers**:
  - `previousTab` ("Previous tab"): `Command+Shift+[` and `Control+Shift+Tab` (`⇧⌘[` / `⌃⇧Tab`)
  - `nextTab` ("Next tab"): `Command+Shift+]` and `Control+Tab` (`⇧⌘]` / `⌃Tab`)
  - `previousThread` ("Previous sidebar item"): `Command+Alt+[` and `Command+Alt+Left` (`⌥⌘[` / `⌥⌘←`)
  - `nextThread` ("Next sidebar item"): `Command+Alt+]` and `Command+Alt+Right` (`⌥⌘]` / `⌥⌘→`)
  - `previousRecentThread` ("Previous recent chat"): `defaultKeybindings: []` (no default shortcut)
  - `nextRecentThread` ("Next recent chat"): `defaultKeybindings: []` (no default shortcut)
- **Impact**: Sending `⌃⇧Tab` / `⌃Tab` switched top-level tabs instead of cycling recently viewed chats, and was a no-op when only one tab was open.
- **Resolution**:
  - `ConfigurationInstaller` now binds `nextRecentThread` to `F19` (`keyCode: 80`) and `previousRecentThread` to `F20` (`keyCode: 90`) in `~/.codex/keybindings.json`.
  - `CodexController` sends `F19` / `F20` for `.nextRecentChat` / `.previousRecentChat`, restoring recent-chat cycling on D-pad Right / Left without stealing `⌃Tab` / `⌃⇧Tab` from keyboard tab navigation.
  - Added selectable actions for **Previous / Next sidebar item** (`⌥⌘[` / `⌥⌘]`, `previousThread` / `nextThread`) and **Previous / Next tab** (`⇧⌘[` / `⇧⌘]`, `previousTab` / `nextTab`).

### 1.2 Push-to-Talk Voice Dictation (`globalDictationHold`)

- **TourBox Micro v0.10 relied on**: `composer.startDictation` having a built-in default of `Ctrl+Shift+D` (`⌃⇧D`)
- **Codex Desktop (`26.1103.60933`) changes**:
  - `composer.startDictation` was removed from the command registry (`module 41251`).
  - `composer.toggleDictation` is restricted to `availableIn: ["browser"]` and disabled (`enabled: false`) in the desktop renderer.
  - Desktop press-and-hold dictation (both in-app when a Codex window is focused and overlay mode otherwise) is now managed by `globalDictationHold` ("Dictation shortcut", `shortcutScope: "os-global"`), which has no built-in default keybinding (`defaultKeybindings: []`) and is only migrated from `composer.startDictation` on Linux (`"linux" === process.platform`).
  - When `globalDictationHold` is bound to `Ctrl+Shift+D` in `~/.codex/keybindings.json`, `globalDictationHotkeyController` registers `Ctrl+Shift+D` and monitors release via `bare-modifier-monitor --release-modifiers control,shift --release-key D --persistent`.
- **Impact**: On fresh or macOS-upgraded Codex installations without an explicit `globalDictationHold` entry, holding `Short` (`⌃⇧D`) no longer started dictation.
- **Resolution**: `ConfigurationInstaller` now installs `{"command": "globalDictationHold", "key": "Ctrl+Shift+D"}` in `~/.codex/keybindings.json` (and removes any retired `composer.startDictation` entry), matching `CodexController.setVoicePressed(_:)`'s press/release sequence.

### 1.3 Quick Chat -> Mini / Popout Overlay (`openAvatarOverlay` / `hotkeyWindow`)

- **TourBox Micro v0.10 sent**: `⌥⌘N` (`keyCode: 45, flags: [.maskAlternate, .maskCommand]`)
- **Codex Desktop (`26.1103.60933`) changes**:
  - `focusQuickChat` was removed and migrated (`focusQuickChat: "openAvatarOverlay"`) to `openAvatarOverlay` ("Show Mini", `shortcutScope: "os-global"`, macOS default `Alt+Space` / `⌥Space`), alongside `hotkeyWindow` ("Popout Window hotkey", commonly bound to `Alt+Space`) and `spotlightSearch` ("Spotlight search", macOS default `Alt+K` / `⌥K`).
  - `⌥⌘N` is unbound in Codex `26.1103.60933`.
- **Resolution**:
  - `.quickChat` (`Tour + Knob press`) now sends `⌥Space` (`keyCode: 49, flags: .maskAlternate`) to trigger the Mini / Popout overlay without forcing the full main window in front of the active workspace first.
  - Added `.spotlightSearch` (`⌥K`, `keyCode: 40, flags: .maskAlternate`) and `.screenshotToCurrentChat` (`⌃⇧4`, `keyCode: 21, flags: [.maskControl, .maskShift]`) as selectable actions.

---

## 2. Full Hardware & Action Mapping Matrix (v0.11.0)

| TourBox Control / Action | TourBox Micro Action | Synthesized Output | Codex Command ID | Status |
|---|---|---|---|---|
| Knob rotate CW / CCW | `.adjustReasoning(±1)` | `F16` / `F17` | `composer.increaseReasoningEffort` / `composer.decreaseReasoningEffort` | Verified (manual record once in Codex) |
| Knob press (default) | `.openModelPicker` | `⌃⇧M` | `composer.openModelPicker` | Verified |
| Scroll wheel | `.scroll(delta)` | Native scroll event | Conversation scroll | Verified |
| Scroll press (default) | `.jumpToLatest` | `⌘↓` | Webview end-of-document | Verified |
| Dial rotate CW / CCW | `.nextChat` / `.previousChat` | `codex://threads/<id>` | Deep-link slot navigation | Verified |
| Dial press (default) | `.searchChats` | `F18` | `searchChats` (managed in `keybindings.json`) | Verified |
| Top (default) | `.newIndependentChat` | `⌥⌘O` | `newProjectlessTask` | Verified |
| Tall (default) | `.approveOrSend` | `Return` | `approval.approve` / `composer.submit` | Verified |
| Side (default) | `.rejectOrCancel` | `Esc` | `approval.decline` / cancel | Verified |
| Short (hold) | `.voice(pressed:)` | `⌃⇧D` press / release | `globalDictationHold` (managed in `keybindings.json`) | Fixed in v0.11.0 |
| C1 / C2 (default) | `.copy` / `.paste` | `⌘C` / `⌘V` | Frontmost app Copy / Paste | Verified |
| D-pad Up (default) | `.screenshot` | `⇧⌘2` | Frontmost screenshot utility | Verified |
| D-pad Right (default) | `.nextRecentChat` | `F19` | `nextRecentThread` (managed in `keybindings.json`) | Fixed in v0.11.0 |
| D-pad Down (default) | `.openReview` | `⌥⌘B` | `toggleSidePanel` ("Toggle Changes panel") | Verified |
| D-pad Left (default) | `.previousRecentChat` | `F20` | `previousRecentThread` (managed in `keybindings.json`) | Fixed in v0.11.0 |
| Tour tap | `.toggleHUD` | Internal | Show / hide six-task HUD | Verified |
| Tour + Knob press | `.quickChat` | `⌥Space` | `openAvatarOverlay` / `hotkeyWindow` | Fixed in v0.11.0 |
| Tour + Scroll press | `.findInChat` | `⌘F` | `findInThread` | Verified |
| Tour + Dial press | `.openCommandMenu` | `⌘K` | `openCommandMenu` | Verified |
| Tour + Top | `.searchFiles` | `⌘P` | `findFiles` | Verified |
| Tour + C1/C2/Up/Right/Down/Left | `.openSlot(1...6)` | `codex://threads/<id>` | Deep-link slot navigation | Verified |
| Optional action | `.toggleFast` | `F13` | `composer.toggleFastMode` (managed in `keybindings.json`) | Verified |
| Optional action | `.togglePlan` | `F14` | `composer.togglePlanMode` (managed in `keybindings.json`) | Verified |
| Optional action | `.forkThread` | `F15` | `forkThread` (managed in `keybindings.json`) | Verified |
| Optional action | `.navigateBack` / `.navigateForward` | `⌘[` / `⌘]` | `navigateBack` / `navigateForward` | Verified |
| Optional action | `.toggleSidebar` | `⌘B` | `toggleSidebar` | Verified |
| Optional action | `.nextNeedingAttention` | `⌥⌘A` | `nextThreadNeedingAttention` | Verified |
| Optional action | `.copyDeepLink` | `⌥⌘L` | `copyDeeplink` | Verified |
| Optional action | `.toggleBottomPanel` | `⌘J` | `toggleBottomPanel` | Verified |
| Optional action | `.openBrowserTab` | `⌘T` | `newTab` (migrated from `openBrowserTab`) | Verified |
| Optional action (new) | `.previousSidebarItem` / `.nextSidebarItem` | `⌥⌘[` / `⌥⌘]` | `previousThread` / `nextThread` | Added in v0.11.0 |
| Optional action (new) | `.previousTab` / `.nextTab` | `⇧⌘[` / `⇧⌘]` | `previousTab` / `nextTab` | Added in v0.11.0 |
| Optional action (new) | `.toggleTerminal` | ``⌃` `` | `toggleTerminal` | Added in v0.11.0 |
| Optional action (new) | `.stepWorkspaceLayout` | `⇧⌘B` | `stepWorkspaceLayout` | Added in v0.11.0 |
| Optional action (new) | `.showFullView` | `⇧⌘F` | `showWorkspaceTabView` | Added in v0.11.0 |
| Optional action (new) | `.openSideChat` | `⌥⌘S` | `openSideChat` | Added in v0.11.0 |
| Optional action (new) | `.archiveChat` | `⇧⌘A` | `archiveThread` | Added in v0.11.0 |
| Optional action (new) | `.togglePinChat` | `⌥⌘P` | `toggleThreadPin` | Added in v0.11.0 |
| Optional action (new) | `.copyWorkingDirectory` | `⇧⌘C` | `copyWorkingDirectory` | Added in v0.11.0 |
| Optional action (new) | `.copyLastCodeBlock` | `⇧⌘;` | `copyLastCodeBlock` | Added in v0.11.0 |
| Optional action (new) | `.toggleVoiceMode` | `⌃⇧V` | `composer.startVoiceMode` | Added in v0.11.0 |
| Optional action (new) | `.spotlightSearch` | `⌥K` | `spotlightSearch` | Added in v0.11.0 |
| Optional action (new) | `.screenshotToCurrentChat` | `⌃⇧4` | `screenshotToCurrentChat` | Added in v0.11.0 |

---

## 3. Lifecycle Hooks, SQLite State Store & Rollout Reconciliation

- **Hooks (`~/.codex/hooks.json`)**: All installed `CodexHookEvent` lifecycle hooks (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Interrupt`, and `Stop`) remain compatible in `codex-cli 0.164.0`.
- **State Database (`~/.codex/state_5.sqlite`)**: `threads` table columns read by `ThreadRepository` (`id`, `title`, `cwd`, `preview`, `recency_at_ms`, `is_pinned`, `rollout_path`, `archived`, `source`) remain intact and indexed by `idx_threads_visible_recency_at_ms`.
- **Rollout JSONL (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`)**: Event types (`task_started`, `task_complete`, `turn_aborted`, `request_user_input`, `agent_message`) remain compatible with `RolloutStateReconciler` and `RolloutPresentationReader`.
