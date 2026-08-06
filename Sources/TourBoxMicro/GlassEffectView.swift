import AppKit
import SwiftUI

/// A single native material layer that can sit behind an entire SwiftUI surface.
/// Child cards should use translucent colors instead of creating more material
/// views, which keeps the glass treatment inexpensive to composite.
struct GlassEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var appearance: NSAppearance.Name? = nil
    var emphasized = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = emphasized
        view.appearance = appearance.flatMap(NSAppearance.init(named:))
    }
}
