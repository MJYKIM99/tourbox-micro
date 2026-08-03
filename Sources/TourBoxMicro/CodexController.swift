import AppKit
import ApplicationServices
import TourBoxCore

@MainActor
final class CodexController {
    private enum ShortcutDestination {
        case codex
        case frontmostApplication
    }

    private let bundleIdentifier = "com.openai.codex"
    private var voiceRequested = false
    private var voiceIsDown = false

    var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

    func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openCodex() {
        _ = activateCodex()
    }

    func openThread(_ thread: CodexThread) {
        guard let url = URL(string: "codex://threads/\(thread.id)") else { return }
        NSWorkspace.shared.open(url)
    }

    func perform(_ action: MicroAction) {
        switch action {
        case .toggleFast:
            shortcut(keyCode: 105)
        case .togglePlan:
            shortcut(keyCode: 107)
        case .forkThread:
            shortcut(keyCode: 113)
        case .approveOrSend:
            shortcut(keyCode: 36)
        case .rejectOrCancel:
            shortcut(keyCode: 53)
        case .voice(let pressed):
            setVoicePressed(pressed)
        case .openReview:
            shortcut(keyCode: 11, flags: [.maskAlternate, .maskCommand])
        case .openModelPicker:
            shortcut(keyCode: 46, flags: [.maskControl, .maskShift])
        case .quickChat:
            shortcut(keyCode: 45, flags: [.maskAlternate, .maskCommand])
        case .findInChat:
            shortcut(keyCode: 3, flags: [.maskCommand])
        case .openCommandMenu:
            shortcut(keyCode: 40, flags: [.maskCommand])
        case .searchFiles:
            shortcut(keyCode: 35, flags: [.maskCommand])
        case .newIndependentChat:
            shortcut(keyCode: 31, flags: [.maskAlternate, .maskCommand])
        case .copy:
            shortcut(keyCode: 8, flags: [.maskCommand], destination: .frontmostApplication)
        case .paste:
            shortcut(keyCode: 9, flags: [.maskCommand], destination: .frontmostApplication)
        case .screenshot:
            shortcut(keyCode: 19, flags: [.maskCommand, .maskShift], destination: .frontmostApplication)
        case .previousRecentChat:
            shortcut(keyCode: 48, flags: [.maskControl, .maskShift])
        case .nextRecentChat:
            shortcut(keyCode: 48, flags: [.maskControl])
        case .adjustReasoning(let delta):
            reasoningShortcut(delta: delta)
        case .searchChats:
            shortcut(keyCode: 5, flags: [.maskCommand])
        case .scroll(let delta):
            scroll(lines: delta * 3)
        case .jumpToLatest:
            shortcut(keyCode: 125, flags: [.maskCommand])
        case .navigateBack:
            shortcut(keyCode: 33, flags: [.maskCommand])
        case .navigateForward:
            shortcut(keyCode: 30, flags: [.maskCommand])
        case .toggleSidebar:
            shortcut(keyCode: 11, flags: [.maskCommand])
        case .previousChat, .nextChat, .openSlot, .toggleHUD:
            break
        }
    }

    func releaseHeldKeys() {
        voiceRequested = false
        if voiceIsDown {
            postKey(keyCode: 2, isDown: false, flags: [.maskControl, .maskShift])
            voiceIsDown = false
        }
    }

    private func setVoicePressed(_ pressed: Bool) {
        voiceRequested = pressed
        if pressed {
            let delay = activationDelay()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.voiceRequested, !self.voiceIsDown else { return }
                self.postKey(keyCode: 2, isDown: true, flags: [.maskControl, .maskShift])
                self.voiceIsDown = true
            }
        } else if voiceIsDown {
            postKey(keyCode: 2, isDown: false, flags: [.maskControl, .maskShift])
            voiceIsDown = false
        }
    }

    private func shortcut(
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        destination: ShortcutDestination = .codex
    ) {
        let delay = destination == .codex ? activationDelay() : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.postKey(keyCode: keyCode, isDown: true, flags: flags)
            self?.postKey(keyCode: keyCode, isDown: false, flags: flags)
        }
    }

    private func reasoningShortcut(delta: Int) {
        // F16/F17 are deliberately character-free and never move the pointer.
        // If Codex has not accepted the user's manual bindings, nothing is inserted
        // into the composer.
        let keyCode: CGKeyCode = delta >= 0 ? 106 : 64
        let count = min(abs(delta), 5)
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.025) { [weak self] in
                self?.postKey(keyCode: keyCode, isDown: true, flags: [])
                self?.postKey(keyCode: keyCode, isDown: false, flags: [])
            }
        }
    }

    private func scroll(lines: Int) {
        let delay = activationDelay()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .hidSystemState)
            let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: Int32(lines),
                wheel2: 0,
                wheel3: 0
            )
            event?.post(tap: .cghidEventTap)
        }
    }

    private func activationDelay() -> TimeInterval {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            return 0
        }
        _ = activateCodex()
        return 0.08
    }

    @discardableResult
    private func activateCodex() -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return running.activate(options: [.activateAllWindows])
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        return true
    }

    private func postKey(keyCode: CGKeyCode, isDown: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}
