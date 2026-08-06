import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    private let onClose: () -> Void

    init(model: SettingsModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let hostingController = NSHostingController(rootView: SettingsRootView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TourBox Micro"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 940, height: 660))
        window.minSize = NSSize(width: 840, height: 600)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
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

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
