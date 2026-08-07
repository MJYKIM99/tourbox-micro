import AppKit
import Pow
import SwiftUI
import TourBoxCore

@MainActor
final class GlassLightsHostingView: NSView {
    private let model: GlassLightsModel
    private let hostingView: NSHostingView<GlassLightsView>

    var onHoverSlotChanged: ((Int?) -> Void)?
    var onOpenSlot: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        let model = GlassLightsModel()
        self.model = model
        hostingView = NSHostingView(rootView: GlassLightsView(model: model))
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        model.onHoverSlotChanged = { [weak self] index in
            self?.onHoverSlotChanged?(index)
        }
        model.onOpenSlot = { [weak self] index in
            self?.onOpenSlot?(index)
        }
    }

    required init?(coder: NSCoder) { nil }

    func update(
        slots: [AgentSlot],
        selectedSlotIndex: Int?,
        animationsEnabled: Bool,
        isVisible: Bool
    ) {
        if model.slots != slots { model.slots = slots }
        if model.selectedSlotIndex != selectedSlotIndex {
            model.selectedSlotIndex = selectedSlotIndex
        }
        if model.animationsEnabled != animationsEnabled {
            model.animationsEnabled = animationsEnabled
        }
        if model.isVisible != isVisible { model.isVisible = isVisible }
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        if model.animationsEnabled != enabled { model.animationsEnabled = enabled }
    }

    func setVisible(_ visible: Bool) {
        if model.isVisible != visible { model.isVisible = visible }
    }
}

@MainActor
private final class GlassLightsModel: ObservableObject {
    @Published var slots: [AgentSlot] = []
    @Published var selectedSlotIndex: Int?
    @Published var animationsEnabled = true
    @Published var isVisible = false

    var onHoverSlotChanged: ((Int?) -> Void)?
    var onOpenSlot: ((Int) -> Void)?
}

@MainActor
private struct GlassLightsView: View {
    @ObservedObject var model: GlassLightsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animationsAreEnabled: Bool {
        model.animationsEnabled && model.isVisible && !reduceMotion
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...6, id: \.self) { index in
                let slot = model.slots.first(where: { $0.index == index })
                    ?? AgentSlot(index: index, thread: nil, state: .off)
                Button {
                    if slot.thread != nil { model.onOpenSlot?(index) }
                } label: {
                    GlassLight(
                        slot: slot,
                        selected: model.selectedSlotIndex == index,
                        animationIsActive: animationsAreEnabled,
                        onHoverChanged: { hovering in
                            model.onHoverSlotChanged?(hovering ? index : nil)
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(slot.thread == nil)
                .accessibilityLabel(accessibilityLabel(for: slot))
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func accessibilityLabel(for slot: AgentSlot) -> String {
        let state = switch slot.state {
        case .off: L10n.tr("Unassigned")
        case .idle: L10n.tr("Idle")
        case .thinking: L10n.tr("Running")
        case .complete: L10n.tr("Completed")
        case .needsInput: L10n.tr("Waiting for input")
        case .error: L10n.tr("Error")
        }
        if let latest = slot.latestMessage, !latest.isEmpty {
            return L10n.format("Task slot %d, %@, %@", slot.index, state, latest)
        }
        return L10n.format("Task slot %d, %@", slot.index, state)
    }
}

@MainActor
private struct GlassLight: View {
    let slot: AgentSlot
    let selected: Bool
    let animationIsActive: Bool
    let onHoverChanged: (Bool) -> Void

    @State private var hovering = false

    private var assigned: Bool { slot.thread != nil }
    private var color: Color {
        guard assigned else { return Color(white: 0.42) }
        return switch slot.state {
        case .off: Color(white: 0.52)
        case .idle: Color(white: 0.92)
        case .thinking: Color(red: 0.24, green: 0.62, blue: 1.00)
        case .complete: Color(red: 0.30, green: 0.94, blue: 0.58)
        case .needsInput: Color(red: 1.00, green: 0.66, blue: 0.30)
        case .error: Color(red: 1.00, green: 0.31, blue: 0.38)
        }
    }

    var body: some View {
        lightBody
        .changeEffect(
            .pulse(
                shape: RoundedRectangle(cornerRadius: 11, style: .continuous),
                style: color.opacity(0.46),
                count: 1
            ),
            value: slot.state.rawValue,
            isEnabled: animationIsActive && assigned && slot.state == .complete
        )
        .changeEffect(
            .shake,
            value: slot.state.rawValue,
            isEnabled: animationIsActive && assigned && slot.state == .error
        )
        .scaleEffect(hovering ? 1.028 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { value in
            hovering = value
            onHoverChanged(value)
        }
    }

    private var lightBody: some View {
        let outerShape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let innerShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let coreShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return ZStack {
            outerShape
                .fill(Color.black.opacity(assigned ? 0.14 : 0.28))
                .overlay {
                    outerShape.fill(Color.white.opacity(assigned ? 0.055 : 0.025))
                }
                .overlay {
                    outerShape.fill(color.opacity(assigned ? 0.24 : 0.035))
                }

            innerShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(assigned ? 0.11 : 0.055),
                            color.opacity(assigned ? 0.20 : 0.025),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    innerShape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.055)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.65
                    )
                }
                .padding(4)

            coreShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(assigned ? 0.20 : 0.13),
                            color.opacity(assigned ? 1.00 : 0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    coreShape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.44), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
                }
                .frame(width: 26, height: 26)
                .shadow(
                    color: color.opacity(assigned ? 0.34 : 0.08),
                    radius: assigned ? 5 : 1.5
                )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.34), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 22, height: 1)
                .offset(y: -16.5)
        }
        .frame(width: 44, height: 44)
        .clipShape(outerShape)
        .overlay {
            outerShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(selected || hovering ? 0.72 : 0.32),
                        Color.white.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: selected ? 1.35 : 0.75
            )
        }
        .contentShape(outerShape)
        .shadow(
            color: assigned ? color.opacity(selected ? 0.22 : 0.11) : .clear,
            radius: selected ? 7 : 5,
            y: 1
        )
    }
}
