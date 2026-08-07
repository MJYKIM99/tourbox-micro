import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    private let onComplete: () -> Void
    private let onClose: () -> Void

    init(
        model: SettingsModel,
        onComplete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.onComplete = onComplete
        self.onClose = onClose
        let hostingController = NSHostingController(
            rootView: OnboardingRootView(model: model, onComplete: onComplete)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.tr("TourBox Micro Setup")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 820, height: 590))
        window.minSize = NSSize(width: 760, height: 550)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        model.refreshDiagnostics()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func finish() {
        onComplete()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
