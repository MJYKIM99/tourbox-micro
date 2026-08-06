import AppKit
import TourBoxCore

@MainActor
final class HUDController {
    private static let taskListSize = NSSize(width: 392, height: 340)
    private static let glassLightsSize = NSSize(width: 322, height: 78)
    private static let taskPeekSize = NSSize(width: 448, height: 142)
    private let screenMargin: CGFloat = 18
    private let panel: NSPanel
    private let glassView: NSVisualEffectView
    private let contentView: HUDCanvasView
    private let peekPanel: NSPanel
    private let peekView: TaskPeekView
    private var style: HUDStyle
    private var hoverDetailsEnabled: Bool
    private var statusNotificationsEnabled: Bool
    private var animationsEnabled: Bool
    private var currentSlots: [AgentSlot] = []
    private var currentSelectedSlotIndex: Int?
    private var currentTourBoxConnected = false
    private var currentStatusText: String?
    private var hoveredSlotIndex: Int?
    private var displayedPeekSlot: AgentSlot?
    private var peekIsHovered = false
    private var hoverDismissTimer: Timer?
    private var transientSlot: AgentSlot?
    private var transientTimer: Timer?
    private var statusTransitionTracker = AgentStatusTransitionTracker()

    var isVisible: Bool { panel.isVisible }
    var onOpenSlot: ((Int) -> Void)?

    init(
        style: HUDStyle,
        hoverDetailsEnabled: Bool,
        statusNotificationsEnabled: Bool,
        animationsEnabled: Bool
    ) {
        self.style = style
        self.hoverDetailsEnabled = hoverDetailsEnabled
        self.statusNotificationsEnabled = statusNotificationsEnabled
        self.animationsEnabled = animationsEnabled
        let size = Self.size(for: style)
        contentView = HUDCanvasView(
            frame: NSRect(origin: .zero, size: size),
            style: style
        )
        glassView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        peekView = TaskPeekView(
            frame: NSRect(origin: .zero, size: Self.taskPeekSize)
        )
        peekPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.taskPeekSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        glassView.material = .hudWindow
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.appearance = NSAppearance(named: .darkAqua)
        glassView.isEmphasized = true
        glassView.wantsLayer = true
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.cornerRadius = Self.cornerRadius(for: style)
        glassView.layer?.masksToBounds = true
        glassView.autoresizingMask = [.width, .height]
        contentView.autoresizingMask = [.width, .height]
        glassView.addSubview(contentView)
        panel.contentView = glassView

        peekPanel.level = .floating
        peekPanel.isOpaque = false
        peekPanel.backgroundColor = .clear
        peekPanel.hasShadow = true
        peekPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        peekPanel.hidesOnDeactivate = false
        peekPanel.isMovableByWindowBackground = false
        peekPanel.isReleasedWhenClosed = false
        peekPanel.ignoresMouseEvents = false
        peekPanel.acceptsMouseMovedEvents = true
        peekPanel.contentView = peekView
        peekPanel.minSize = Self.taskPeekSize
        peekPanel.maxSize = Self.taskPeekSize
        peekPanel.contentMinSize = Self.taskPeekSize
        peekPanel.contentMaxSize = Self.taskPeekSize
        peekPanel.setContentSize(Self.taskPeekSize)

        // Keep all sizing rules on the window itself. The custom HUD view draws
        // into these bounds and has no intrinsic content size, so long task names
        // can never expand the panel.
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setContentSize(size)

        contentView.onHoverSlotChanged = { [weak self] index in
            self?.handleHoverSlotChanged(index)
        }
        contentView.onOpenSlot = { [weak self] index in
            self?.openSlotFromHUD(index)
        }
        contentView.setAnimationsEnabled(animationsEnabled)
        contentView.setVisible(false)
        peekView.onHoverChanged = { [weak self] hovering in
            self?.handlePeekHoverChanged(hovering)
        }
        peekView.onOpen = { [weak self] in
            self?.openDisplayedPeekSlot()
        }

        positionAtAnchor()
    }

    func show() {
        repairCompactFrame()
        contentView.setVisible(true)
        panel.orderFrontRegardless()
        refreshPeek()
    }

    func hide() {
        contentView.setVisible(false)
        panel.orderOut(nil)
        hoverDismissTimer?.invalidate()
        hoverDismissTimer = nil
        transientTimer?.invalidate()
        transientTimer = nil
        transientSlot = nil
        hoveredSlotIndex = nil
        displayedPeekSlot = nil
        peekIsHovered = false
        peekPanel.orderOut(nil)
    }

    func close() {
        hide()
        peekPanel.close()
        panel.close()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func setStyle(_ style: HUDStyle) {
        guard style != self.style else { return }
        self.style = style
        contentView.setStyle(style)
        applySizeAndPosition()
        if style != .glassLights {
            hoverDismissTimer?.invalidate()
            hoverDismissTimer = nil
            hoveredSlotIndex = nil
            displayedPeekSlot = nil
            peekIsHovered = false
            peekPanel.orderOut(nil)
        }
        if isVisible {
            panel.orderFrontRegardless()
            refreshPeek()
        }
    }

    func setHoverDetailsEnabled(_ enabled: Bool) {
        hoverDetailsEnabled = enabled
        if !enabled {
            hoverDismissTimer?.invalidate()
            hoverDismissTimer = nil
            hoveredSlotIndex = nil
            peekIsHovered = false
        }
        refreshPeek()
    }

    func setStatusNotificationsEnabled(_ enabled: Bool) {
        statusNotificationsEnabled = enabled
        if !enabled {
            transientTimer?.invalidate()
            transientTimer = nil
            transientSlot = nil
        }
        refreshPeek()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard enabled != animationsEnabled else { return }
        animationsEnabled = enabled
        contentView.setAnimationsEnabled(enabled)
    }

    func update(
        slots: [AgentSlot],
        selectedSlotIndex: Int?,
        tourBoxConnected: Bool,
        statusText: String? = nil
    ) {
        guard slots != currentSlots
                || selectedSlotIndex != currentSelectedSlotIndex
                || tourBoxConnected != currentTourBoxConnected
                || statusText != currentStatusText else { return }
        repairCompactFrame()
        let notificationSlot = statusTransitionTracker.notificationCandidate(in: slots)
        currentSlots = slots
        currentSelectedSlotIndex = selectedSlotIndex
        currentTourBoxConnected = tourBoxConnected
        currentStatusText = statusText
        contentView.update(
            slots: slots,
            selectedSlotIndex: selectedSlotIndex,
            tourBoxConnected: tourBoxConnected,
            statusText: statusText
        )
        if let notificationSlot {
            presentTransientStatus(for: notificationSlot)
        } else {
            refreshPeek()
        }
    }

    func resetPosition() {
        positionAtAnchor()
        show()
    }

    private static func size(for style: HUDStyle) -> NSSize {
        switch style {
        case .glassLights: glassLightsSize
        case .taskList: taskListSize
        }
    }

    private static func cornerRadius(for style: HUDStyle) -> CGFloat {
        switch style {
        case .glassLights: 18
        case .taskList: 14
        }
    }

    private var currentSize: NSSize { Self.size(for: style) }

    private func applySizeAndPosition() {
        let size = currentSize
        panel.minSize = .zero
        panel.maxSize = NSSize(width: 10_000, height: 10_000)
        panel.contentMinSize = .zero
        panel.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        panel.setContentSize(size)
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        glassView.frame = NSRect(origin: .zero, size: size)
        glassView.layer?.cornerRadius = Self.cornerRadius(for: style)
        contentView.frame = NSRect(origin: .zero, size: size)
        positionAtAnchor()
    }

    private func positionAtAnchor() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        panel.setFrame(frameAtAnchor(in: visibleFrame), display: true)
        contentView.frame = NSRect(origin: .zero, size: currentSize)
        if peekPanel.isVisible { positionPeekPanel() }
    }

    private func frameAtAnchor(in visibleFrame: NSRect) -> NSRect {
        let size = currentSize
        switch style {
        case .glassLights:
            return NSRect(
                x: visibleFrame.minX + screenMargin,
                y: visibleFrame.minY + screenMargin,
                width: size.width,
                height: size.height
            )
        case .taskList:
            return NSRect(
                x: visibleFrame.maxX - size.width - screenMargin,
                y: visibleFrame.maxY - size.height - screenMargin,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Repairs both accidental window-manager resizing and historical frames
    /// produced by intrinsic text widths in the previous Auto Layout HUD.
    private func repairCompactFrame() {
        guard let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let current = panel.frame
        let size = currentSize
        let sizeWasChanged = abs(current.width - size.width) > 0.5
            || abs(current.height - size.height) > 0.5

        if sizeWasChanged {
            panel.setFrame(frameAtAnchor(in: visibleFrame), display: true)
            contentView.frame = NSRect(origin: .zero, size: size)
            return
        }

        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = max(minimumX, visibleFrame.maxX - size.width - screenMargin)
        let minimumY = visibleFrame.minY + screenMargin
        let maximumY = max(minimumY, visibleFrame.maxY - size.height - screenMargin)
        let clampedOrigin = NSPoint(
            x: min(max(current.minX, minimumX), maximumX),
            y: min(max(current.minY, minimumY), maximumY)
        )
        if abs(clampedOrigin.x - current.minX) > 0.5
            || abs(clampedOrigin.y - current.minY) > 0.5 {
            panel.setFrameOrigin(clampedOrigin)
            if peekPanel.isVisible { positionPeekPanel() }
        }
    }

    private func handleHoverSlotChanged(_ index: Int?) {
        guard hoverDetailsEnabled else { return }
        if let index {
            hoverDismissTimer?.invalidate()
            hoverDismissTimer = nil
            hoveredSlotIndex = index
            refreshPeek()
        } else {
            scheduleHoverDismissal()
        }
    }

    private func handlePeekHoverChanged(_ hovering: Bool) {
        peekIsHovered = hovering
        if hovering {
            hoverDismissTimer?.invalidate()
            hoverDismissTimer = nil
        } else {
            scheduleHoverDismissal()
        }
    }

    private func scheduleHoverDismissal() {
        hoverDismissTimer?.invalidate()
        let timer = Timer(timeInterval: 0.32, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.peekIsHovered else { return }
                self.hoveredSlotIndex = nil
                self.hoverDismissTimer = nil
                self.refreshPeek()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverDismissTimer = timer
    }

    private func openSlotFromHUD(_ index: Int) {
        guard currentSlots.first(where: { $0.index == index })?.thread != nil else {
            NSSound.beep()
            return
        }
        hoverDismissTimer?.invalidate()
        hoverDismissTimer = nil
        hoveredSlotIndex = nil
        displayedPeekSlot = nil
        peekIsHovered = false
        peekPanel.orderOut(nil)
        onOpenSlot?(index)
    }

    private func openDisplayedPeekSlot() {
        guard let threadID = displayedPeekSlot?.thread?.id,
              let currentSlot = currentSlots.first(where: { $0.thread?.id == threadID }) else {
            NSSound.beep()
            return
        }
        openSlotFromHUD(currentSlot.index)
    }

    private func presentTransientStatus(for slot: AgentSlot) {
        guard statusNotificationsEnabled else { return }
        transientSlot = slot
        transientTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.transientSlot = nil
                self?.transientTimer = nil
                self?.refreshPeek()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        transientTimer = timer
        refreshPeek()
    }

    private func refreshPeek() {
        guard isVisible, style == .glassLights else {
            peekPanel.orderOut(nil)
            displayedPeekSlot = nil
            peekIsHovered = false
            return
        }

        if hoverDetailsEnabled,
           let hoveredSlotIndex,
           let slot = currentSlots.first(where: { $0.index == hoveredSlotIndex }) {
            showPeek(for: slot, transient: false)
            return
        }
        if statusNotificationsEnabled, let transientSlot {
            showPeek(for: transientSlot, transient: true)
            return
        }
        peekPanel.orderOut(nil)
        displayedPeekSlot = nil
        peekIsHovered = false
    }

    private func showPeek(for slot: AgentSlot, transient: Bool) {
        displayedPeekSlot = slot
        peekView.update(slot: slot, transient: transient)
        positionPeekPanel()
        peekPanel.orderFrontRegardless()
    }

    private func positionPeekPanel() {
        guard let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = Self.taskPeekSize
        let preferredX = panel.frame.minX
        let x = min(
            max(preferredX, visibleFrame.minX + screenMargin),
            visibleFrame.maxX - size.width - screenMargin
        )
        let preferredY = panel.frame.maxY + 8
        let y = min(preferredY, visibleFrame.maxY - size.height - screenMargin)
        peekPanel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true
        )
        peekView.frame = NSRect(origin: .zero, size: size)
    }
}

@MainActor
private final class HUDCanvasView: NSView {
    private enum Metrics {
        static let outerInset: CGFloat = 10
        static let headerHeight: CGFloat = 42
        static let rowTop: CGFloat = 50
        static let rowHeight: CGFloat = 38
        static let rowGap: CGFloat = 4
        static let footerTop: CGFloat = 306
    }

    private enum Palette {
        static let shell = NSColor(calibratedWhite: 0.02, alpha: 0.22)
        static let shellEdge = NSColor.white.withAlphaComponent(0.34)
        static let hairline = NSColor.white.withAlphaComponent(0.14)
        static let row = NSColor(calibratedWhite: 0.03, alpha: 0.28)
        static let rowAlternate = NSColor(calibratedWhite: 0.12, alpha: 0.30)
        static let paper = NSColor(calibratedWhite: 0.88, alpha: 1)
        static let ink = NSColor(calibratedWhite: 0.055, alpha: 1)
        static let primary = NSColor(calibratedWhite: 0.92, alpha: 1)
        static let secondary = NSColor(calibratedWhite: 0.60, alpha: 1)
        static let muted = NSColor(calibratedWhite: 0.40, alpha: 1)
    }

    private var slots: [AgentSlot] = []
    private var selectedSlotIndex: Int?
    private var tourBoxConnected = false
    private var statusText = "等待 TourBox"
    private var style: HUDStyle
    private var hoverTrackingArea: NSTrackingArea?
    private var reportedHoverSlotIndex: Int?
    private var animationsEnabled = true
    private var contentVisible = false
    private var glassLightsView: GlassLightsHostingView?

    var onHoverSlotChanged: ((Int?) -> Void)?
    var onOpenSlot: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

    init(frame frameRect: NSRect, style: HUDStyle) {
        self.style = style
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        if style == .glassLights { installGlassLightsView() }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibilityLabel()
    }

    required init?(coder: NSCoder) { nil }

    func setStyle(_ style: HUDStyle) {
        guard style != self.style else { return }
        self.style = style
        if style == .glassLights {
            installGlassLightsView()
        } else {
            reportHoverSlot(nil)
            glassLightsView?.removeFromSuperview()
            glassLightsView = nil
        }
        updateTrackingAreas()
        needsDisplay = true
    }

    private func installGlassLightsView() {
        guard glassLightsView == nil else { return }
        let view = GlassLightsHostingView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.onHoverSlotChanged = { [weak self] index in
            self?.reportHoverSlot(index)
        }
        view.onOpenSlot = { [weak self] index in
            self?.onOpenSlot?(index)
        }
        view.update(
            slots: slots,
            selectedSlotIndex: selectedSlotIndex,
            animationsEnabled: animationsEnabled,
            isVisible: contentVisible
        )
        addSubview(view)
        glassLightsView = view
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard animationsEnabled != enabled else { return }
        animationsEnabled = enabled
        glassLightsView?.setAnimationsEnabled(enabled)
        needsDisplay = true
    }

    func setVisible(_ visible: Bool) {
        guard contentVisible != visible else { return }
        contentVisible = visible
        glassLightsView?.setVisible(visible)
        if !visible { reportHoverSlot(nil) }
    }

    func update(
        slots: [AgentSlot],
        selectedSlotIndex: Int?,
        tourBoxConnected: Bool,
        statusText: String?
    ) {
        let nextStatusText = statusText ?? (tourBoxConnected ? "TourBox 已连接" : "等待 TourBox")
        guard slots != self.slots
                || selectedSlotIndex != self.selectedSlotIndex
                || tourBoxConnected != self.tourBoxConnected
                || nextStatusText != self.statusText else { return }
        self.slots = slots
        self.selectedSlotIndex = selectedSlotIndex
        self.tourBoxConnected = tourBoxConnected
        self.statusText = nextStatusText
        glassLightsView?.update(
            slots: slots,
            selectedSlotIndex: selectedSlotIndex,
            animationsEnabled: animationsEnabled,
            isVisible: contentVisible
        )
        updateAccessibilityLabel()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        hoverTrackingArea = nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard style == .glassLights else { return }
        let point = convert(event.locationInWindow, from: nil)
        reportHoverSlot(glassSlotIndex(at: point))
    }

    override func mouseExited(with event: NSEvent) {
        reportHoverSlot(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard style == .glassLights else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = glassSlotIndex(at: point),
              slots.first(where: { $0.index == index })?.thread != nil else {
            super.mouseDown(with: event)
            return
        }
        onOpenSlot?(index)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard style == .glassLights else { return }
        for index in 1...6 where slots.first(where: { $0.index == index })?.thread != nil {
            addCursorRect(glassCellRect(for: index), cursor: .pointingHand)
        }
    }

    private func glassSlotIndex(at point: NSPoint) -> Int? {
        for index in 1...6 {
            if glassCellRect(for: index).contains(point) { return index }
        }
        return nil
    }

    private func glassCellRect(for index: Int) -> NSRect {
        let cellSize: CGFloat = 44
        let gap: CGFloat = 8
        let startX: CGFloat = 9
        return NSRect(
            x: startX + CGFloat(index - 1) * (cellSize + gap),
            y: (bounds.height - cellSize) / 2,
            width: cellSize,
            height: cellSize
        )
    }

    private func reportHoverSlot(_ index: Int?) {
        guard index != reportedHoverSlotIndex else { return }
        reportedHoverSlotIndex = index
        needsDisplay = true
        onHoverSlotChanged?(index)
    }

    override func layout() {
        super.layout()
        glassLightsView?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        switch style {
        case .glassLights:
            break
        case .taskList:
            drawShell()
            drawHeader()
            for index in 1...6 {
                drawRow(index: index)
            }
            drawFooter()
        }
    }

    private func drawGlassLights() {
        for index in 1...6 {
            let slot = slots.first(where: { $0.index == index })
            let assigned = slot?.thread != nil
            let state = slot?.state ?? .off
            drawGlassCell(
                in: glassCellRect(for: index),
                index: index,
                state: state,
                assigned: assigned,
                selected: selectedSlotIndex == index,
                hovered: reportedHoverSlotIndex == index
            )
        }
    }

    private func drawGlassCell(
        in rect: NSRect,
        index: Int,
        state: AgentState,
        assigned: Bool,
        selected: Bool,
        hovered: Bool
    ) {
        let color = glassColor(for: state, assigned: assigned)
        let time = Date.timeIntervalSinceReferenceDate
        let statePulse = animationPulse(for: state, index: index, time: time)
        let selectedPulse = selected
            ? 0.74 + 0.26 * CGFloat((sin(time * 3.2) + 1) / 2)
            : 0
        let pulse = max(statePulse, selectedPulse)
        let outerPath = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)

        if animationsEnabled, state == .complete, assigned {
            drawCompletionRipple(in: rect, color: color, index: index, time: time)
        }

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color.withAlphaComponent((assigned ? 0.82 : 0.24) * pulse)
        glow.shadowBlurRadius = assigned ? 11 + 6 * pulse : 5
        glow.shadowOffset = .zero
        glow.set()
        color.withAlphaComponent((assigned ? 0.34 : 0.12) * pulse).setFill()
        outerPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let baseGradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.30, alpha: 0.78),
            NSColor(calibratedWhite: 0.065, alpha: 0.91)
        ])
        baseGradient?.draw(in: outerPath, angle: -90)

        color.withAlphaComponent(assigned ? 0.26 : 0.08).setFill()
        outerPath.fill()

        if animationsEnabled, state == .thinking, assigned {
            drawThinkingShimmer(in: rect, clippedTo: outerPath, index: index, time: time)
        }

        let innerRect = rect.insetBy(dx: 4.5, dy: 4.5)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 8, yRadius: 8)
        let innerGradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.30),
            color.withAlphaComponent(assigned ? 0.16 : 0.04),
            NSColor.black.withAlphaComponent(0.24)
        ])
        innerGradient?.draw(in: innerPath, angle: -90)

        NSColor.white.withAlphaComponent(0.42).setStroke()
        outerPath.lineWidth = 0.85
        outerPath.stroke()
        NSColor.white.withAlphaComponent(0.20).setStroke()
        innerPath.lineWidth = 0.55
        innerPath.stroke()

        let highlightRect = NSRect(
            x: innerRect.minX + 3,
            y: innerRect.minY + 2,
            width: innerRect.width - 6,
            height: max(5, innerRect.height * 0.34)
        )
        let highlight = NSBezierPath(
            roundedRect: highlightRect,
            xRadius: 5,
            yRadius: 5
        )
        NSColor.white.withAlphaComponent(0.10).setFill()
        highlight.fill()

        let lightRect = innerRect.insetBy(dx: 7, dy: 7)
        let lightPath = NSBezierPath(roundedRect: lightRect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        let lightGlow = NSShadow()
        lightGlow.shadowColor = color.withAlphaComponent((assigned ? 0.95 : 0.30) * pulse)
        lightGlow.shadowBlurRadius = assigned ? 9 + 7 * pulse : 3
        lightGlow.shadowOffset = .zero
        lightGlow.set()
        let lightGradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(assigned ? 0.40 : 0.16),
            color.withAlphaComponent(assigned ? 0.92 : 0.24)
        ])
        lightGradient?.draw(in: lightPath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        if hovered {
            NSColor.white.withAlphaComponent(0.82).setStroke()
            let hoverPath = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 12, yRadius: 12)
            hoverPath.lineWidth = 1.4
            hoverPath.stroke()
        }
    }

    private func animationPulse(
        for state: AgentState,
        index: Int,
        time: TimeInterval
    ) -> CGFloat {
        guard animationsEnabled,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 1 }
        let offsetTime = time + Double(index) * 0.17
        switch state {
        case .thinking:
            return 0.72 + 0.28 * CGFloat((sin(offsetTime * 2.25) + 1) / 2)
        case .complete:
            let phase = offsetTime.truncatingRemainder(dividingBy: 3.4)
            let wave = phase < 0.85 ? sin((phase / 0.85) * .pi) : 0
            return 0.82 + 0.18 * CGFloat(max(0, wave))
        case .needsInput:
            return 0.68 + 0.32 * CGFloat((sin(offsetTime * 3.0) + 1) / 2)
        case .error:
            let phase = offsetTime.truncatingRemainder(dividingBy: 2.4)
            let first = max(0, 1 - abs(phase - 0.18) / 0.16)
            let second = max(0, 1 - abs(phase - 0.48) / 0.18)
            return 0.70 + 0.30 * CGFloat(max(first, second))
        case .idle, .off:
            return 0.94
        }
    }

    private func drawCompletionRipple(
        in rect: NSRect,
        color: NSColor,
        index: Int,
        time: TimeInterval
    ) {
        let phase = (time + Double(index) * 0.17).truncatingRemainder(dividingBy: 3.4)
        guard phase < 1.05 else { return }
        let progress = CGFloat(phase / 1.05)
        let expansion = 1 + progress * 3.2
        let ripple = NSBezierPath(
            roundedRect: rect.insetBy(dx: -expansion, dy: -expansion),
            xRadius: 12 + expansion,
            yRadius: 12 + expansion
        )
        color.withAlphaComponent(0.40 * (1 - progress)).setStroke()
        ripple.lineWidth = 1.1
        ripple.stroke()
    }

    private func drawThinkingShimmer(
        in rect: NSRect,
        clippedTo clipPath: NSBezierPath,
        index: Int,
        time: TimeInterval
    ) {
        let travel = (time * 22 + Double(index) * 9)
            .truncatingRemainder(dividingBy: Double(rect.width + 32))
        let x = rect.minX - 18 + CGFloat(travel)
        let shimmerRect = NSRect(x: x, y: rect.minY - 3, width: 10, height: rect.height + 6)
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        let shimmer = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0),
            NSColor.white.withAlphaComponent(0.22),
            NSColor.white.withAlphaComponent(0)
        ])
        shimmer?.draw(in: shimmerRect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func glassColor(for state: AgentState, assigned: Bool) -> NSColor {
        guard assigned else { return NSColor(calibratedWhite: 0.36, alpha: 1) }
        return switch state {
        case .off: NSColor(calibratedWhite: 0.60, alpha: 1)
        case .idle: NSColor(calibratedWhite: 0.96, alpha: 1)
        case .thinking: NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.00, alpha: 1)
        case .complete: NSColor(calibratedRed: 0.32, green: 1.00, blue: 0.58, alpha: 1)
        case .needsInput: NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.34, alpha: 1)
        case .error: NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    private func drawShell() {
        let shellRect = bounds.insetBy(dx: 1, dy: 1)
        let shellPath = NSBezierPath(roundedRect: shellRect, xRadius: 8, yRadius: 8)
        Palette.shell.setFill()
        shellPath.fill()
        Palette.shellEdge.setStroke()
        shellPath.lineWidth = 1
        shellPath.stroke()

        let innerRect = bounds.insetBy(dx: 5, dy: 5)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 5, yRadius: 5)
        Palette.hairline.withAlphaComponent(0.55).setStroke()
        innerPath.lineWidth = 0.5
        innerPath.stroke()
    }

    private func drawHeader() {
        drawText(
            "TOURBOX MICRO",
            in: NSRect(x: 15, y: 12, width: 150, height: 14),
            font: .monospacedSystemFont(ofSize: 11, weight: .bold),
            color: Palette.primary,
            letterSpacing: 0.8
        )
        drawText(
            "TASK DECK / 06",
            in: NSRect(x: 15, y: 26, width: 150, height: 11),
            font: .monospacedSystemFont(ofSize: 8, weight: .medium),
            color: Palette.secondary,
            letterSpacing: 0.5
        )

        let lampRect = NSRect(x: bounds.width - 105, y: 16, width: 7, height: 7)
        let lamp = NSBezierPath(ovalIn: lampRect)
        (tourBoxConnected ? Palette.paper : Palette.muted).setFill()
        lamp.fill()
        Palette.shellEdge.setStroke()
        lamp.lineWidth = 0.7
        lamp.stroke()

        drawText(
            tourBoxConnected ? "LINKED" : "STANDBY",
            in: NSRect(x: bounds.width - 92, y: 12, width: 77, height: 14),
            font: .monospacedSystemFont(ofSize: 9, weight: .semibold),
            color: tourBoxConnected ? Palette.primary : Palette.secondary,
            alignment: .right,
            letterSpacing: 0.5
        )
        drawText(
            tourBoxConnected ? "TCP / 50500" : "NO SIGNAL",
            in: NSRect(x: bounds.width - 108, y: 26, width: 93, height: 11),
            font: .monospacedSystemFont(ofSize: 7.5, weight: .regular),
            color: Palette.secondary,
            alignment: .right,
            letterSpacing: 0.35
        )

        strokeLine(
            from: NSPoint(x: Metrics.outerInset, y: Metrics.headerHeight),
            to: NSPoint(x: bounds.width - Metrics.outerInset, y: Metrics.headerHeight),
            color: Palette.hairline
        )
    }

    private func drawRow(index: Int) {
        let y = Metrics.rowTop + CGFloat(index - 1) * (Metrics.rowHeight + Metrics.rowGap)
        let rowRect = NSRect(
            x: Metrics.outerInset,
            y: y,
            width: bounds.width - Metrics.outerInset * 2,
            height: Metrics.rowHeight
        )
        let rowPath = NSBezierPath(roundedRect: rowRect, xRadius: 3, yRadius: 3)
        (index.isMultiple(of: 2) ? Palette.rowAlternate : Palette.row).setFill()
        rowPath.fill()
        Palette.hairline.withAlphaComponent(0.64).setStroke()
        rowPath.lineWidth = 0.6
        rowPath.stroke()

        let slot = slots.first(where: { $0.index == index })
        let isAssigned = slot?.thread != nil
        let keyRect = NSRect(x: rowRect.minX + 7, y: rowRect.minY + 7, width: 24, height: 24)
        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: 2, yRadius: 2)
        if isAssigned {
            Palette.paper.setFill()
            keyPath.fill()
        } else {
            Palette.hairline.withAlphaComponent(0.55).setFill()
            keyPath.fill()
        }
        Palette.shellEdge.setStroke()
        keyPath.lineWidth = 0.6
        keyPath.stroke()
        drawText(
            String(format: "%02d", index),
            in: NSRect(x: keyRect.minX, y: keyRect.minY + 5, width: keyRect.width, height: 13),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            color: isAssigned ? Palette.ink : Palette.secondary,
            alignment: .center
        )

        let state = slot?.state ?? .off
        let status = statusCode(for: state, assigned: isAssigned)
        let statusWidth: CGFloat = 58
        let statusX = rowRect.maxX - statusWidth - 8
        drawStateMarker(state: state, assigned: isAssigned, x: statusX, centerY: rowRect.midY)
        drawText(
            status,
            in: NSRect(x: statusX + 11, y: rowRect.minY + 7, width: statusWidth - 11, height: 12),
            font: .monospacedSystemFont(ofSize: 8, weight: .semibold),
            color: stateColor(for: state, assigned: isAssigned),
            alignment: .right,
            letterSpacing: 0.25
        )

        let textX = keyRect.maxX + 9
        let textWidth = max(20, statusX - textX - 7)
        if let thread = slot?.thread {
            drawText(
                thread.title,
                in: NSRect(x: textX, y: rowRect.minY + 5, width: textWidth, height: 14),
                font: .systemFont(ofSize: 10.5, weight: .semibold),
                color: Palette.primary
            )
            drawText(
                detailText(for: slot, cwd: thread.cwd),
                in: NSRect(x: textX, y: rowRect.minY + 21, width: textWidth + statusWidth - 2, height: 10),
                font: .monospacedSystemFont(ofSize: 7.5, weight: .regular),
                color: Palette.secondary,
                letterSpacing: 0.15
            )
        } else {
            drawText(
                "UNASSIGNED",
                in: NSRect(x: textX, y: rowRect.minY + 6, width: textWidth, height: 13),
                font: .monospacedSystemFont(ofSize: 9.5, weight: .medium),
                color: Palette.secondary,
                letterSpacing: 0.45
            )
            drawText(
                "TOUR + \(slotKey(for: index))",
                in: NSRect(x: textX, y: rowRect.minY + 21, width: textWidth, height: 10),
                font: .monospacedSystemFont(ofSize: 7.5, weight: .regular),
                color: Palette.muted,
                letterSpacing: 0.2
            )
        }
    }

    private func drawFooter() {
        strokeLine(
            from: NSPoint(x: Metrics.outerInset, y: Metrics.footerTop - 4),
            to: NSPoint(x: bounds.width - Metrics.outerInset, y: Metrics.footerTop - 4),
            color: Palette.hairline
        )
        drawText(
            "TOUR +",
            in: NSRect(x: 15, y: Metrics.footerTop + 4, width: 49, height: 12),
            font: .monospacedSystemFont(ofSize: 8, weight: .semibold),
            color: Palette.secondary,
            letterSpacing: 0.35
        )
        drawText(
            "C1   C2   ↑   →   ↓   ←",
            in: NSRect(x: 65, y: Metrics.footerTop + 3, width: 205, height: 13),
            font: .monospacedSystemFont(ofSize: 9, weight: .medium),
            color: Palette.primary,
            letterSpacing: 0.25
        )
        drawText(
            "DRAG TO MOVE",
            in: NSRect(x: bounds.width - 112, y: Metrics.footerTop + 4, width: 97, height: 12),
            font: .monospacedSystemFont(ofSize: 7.5, weight: .regular),
            color: Palette.muted,
            alignment: .right,
            letterSpacing: 0.25
        )
    }

    private func drawStateMarker(state: AgentState, assigned: Bool, x: CGFloat, centerY: CGFloat) {
        let markerRect = NSRect(x: x, y: centerY - 3, width: 6, height: 6)
        let marker: NSBezierPath
        switch state {
        case .complete, .needsInput:
            marker = NSBezierPath(rect: markerRect)
        default:
            marker = NSBezierPath(ovalIn: markerRect)
        }
        let color = stateColor(for: state, assigned: assigned)
        if state == .off || state == .idle {
            color.setStroke()
            marker.lineWidth = 0.8
            marker.stroke()
        } else {
            color.setFill()
            marker.fill()
        }
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail,
        letterSpacing: CGFloat = 0
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        paragraph.maximumLineHeight = rect.height
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: letterSpacing
        ]
        NSAttributedString(string: text, attributes: attributes).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    private func strokeLine(from start: NSPoint, to end: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 0.6
        color.setStroke()
        path.stroke()
    }

    private func statusCode(for state: AgentState, assigned: Bool) -> String {
        guard assigned else { return "EMPTY" }
        return switch state {
        case .off: "OFF"
        case .idle: "IDLE"
        case .thinking: "RUN"
        case .complete: "DONE"
        case .needsInput: "INPUT"
        case .error: "ERROR"
        }
    }

    private func stateColor(for state: AgentState, assigned: Bool) -> NSColor {
        guard assigned else { return Palette.muted }
        return switch state {
        case .off: Palette.muted
        case .idle: NSColor(calibratedWhite: 0.94, alpha: 1)
        case .thinking: NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.00, alpha: 1)
        case .complete: NSColor(calibratedRed: 0.32, green: 1.00, blue: 0.58, alpha: 1)
        case .needsInput: NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.34, alpha: 1)
        case .error: NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    private func detailText(for slot: AgentSlot?, cwd: String) -> String {
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = project.isEmpty ? "CODEX" : project.uppercased()
        guard let detail = slot?.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return projectName
        }
        return "\(projectName) / \(detail.uppercased())"
    }

    private func slotKey(for index: Int) -> String {
        switch index {
        case 1: "C1"
        case 2: "C2"
        case 3: "UP"
        case 4: "RIGHT"
        case 5: "DOWN"
        case 6: "LEFT"
        default: "KEY"
        }
    }

    private func updateAccessibilityLabel() {
        let slotSummary = slots.map { slot in
            let title = slot.thread?.title ?? "未分配"
            return "\(slot.index) \(title) \(statusCode(for: slot.state, assigned: slot.thread != nil))"
        }.joined(separator: ", ")
        setAccessibilityLabel("TourBox Micro HUD，\(statusText)，\(slotSummary)")
    }
}

@MainActor
private final class TaskPeekView: NSView {
    private var slot = AgentSlot(index: 1, thread: nil, state: .off)
    private var transient = false
    private var hovered = false
    private var hoverTrackingArea: NSTrackingArea?
    private let effectView = NSVisualEffectView()
    private let statusDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "未分配任务")
    private let projectIcon = NSImageView()
    private let projectLabel = NSTextField(labelWithString: "没有项目")
    private let statusLabel = NSTextField(labelWithString: "未分配")
    private let divider = NSBox()
    private let messageLabel = NSTextField(wrappingLabelWithString: "这个灯位目前没有分配任务")
    private let rendersLegacyDrawing = false

    var onHoverChanged: ((Bool) -> Void)?
    var onOpen: (() -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.isEmphasized = true
        effectView.autoresizingMask = [.width, .height]

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.shadowOffset = .zero
        statusDot.layer?.shadowRadius = 7
        statusDot.layer?.shadowOpacity = 0.84

        titleLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        projectIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        projectIcon.imageScaling = .scaleProportionallyDown
        projectIcon.contentTintColor = NSColor.white.withAlphaComponent(0.46)

        projectLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        projectLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        projectLabel.lineBreakMode = .byTruncatingMiddle
        projectLabel.maximumNumberOfLines = 1

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.alignment = .right

        divider.boxType = .separator
        divider.borderColor = NSColor.white.withAlphaComponent(0.10)

        messageLabel.font = .systemFont(ofSize: 13.8, weight: .regular)
        messageLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.cell?.wraps = true
        messageLabel.cell?.truncatesLastVisibleLine = true
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(effectView)
        addSubview(statusDot)
        addSubview(titleLabel)
        addSubview(projectIcon)
        addSubview(projectLabel)
        addSubview(statusLabel)
        addSubview(divider)
        addSubview(messageLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateContent()
        updateAccessibilityLabel()
    }

    required init?(coder: NSCoder) { nil }

    func update(slot: AgentSlot, transient: Bool) {
        self.slot = slot
        self.transient = transient
        updateContent()
        updateAccessibilityLabel()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateBorder()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateBorder()
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard slot.thread != nil else {
            NSSound.beep()
            return
        }
        onOpen?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if slot.thread != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        statusDot.frame = NSRect(x: 18, y: 18, width: 8, height: 8)
        titleLabel.frame = NSRect(x: 36, y: 9, width: max(0, bounds.width - 160), height: 22)
        statusLabel.frame = NSRect(x: bounds.width - 116, y: 11, width: 98, height: 18)
        projectIcon.frame = NSRect(x: 36, y: 36, width: 13, height: 13)
        projectLabel.frame = NSRect(x: 55, y: 32, width: max(0, bounds.width - 73), height: 20)
        divider.frame = NSRect(x: 18, y: 59, width: max(0, bounds.width - 36), height: 1)
        messageLabel.frame = NSRect(x: 18, y: 70, width: max(0, bounds.width - 36), height: 56)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard rendersLegacyDrawing else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let assigned = slot.thread != nil
        let accent = stateColor(slot.state, assigned: assigned)
        let shell = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.6, dy: 0.6), xRadius: 17, yRadius: 17)
        NSColor.black.withAlphaComponent(0.12).setFill()
        shell.fill()
        NSColor.white.withAlphaComponent(hovered ? 0.42 : 0.24).setStroke()
        shell.lineWidth = hovered ? 1.1 : 0.7
        shell.stroke()

        let dotRect = NSRect(x: 18, y: 18, width: 8, height: 8)
        let dot = NSBezierPath(ovalIn: dotRect)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.84)
        glow.shadowBlurRadius = 7
        glow.shadowOffset = .zero
        glow.set()
        accent.setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()

        let slotRect = NSRect(x: 36, y: 10, width: 38, height: 24)
        let slotPath = NSBezierPath(roundedRect: slotRect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.08).setFill()
        slotPath.fill()
        NSColor.white.withAlphaComponent(0.15).setStroke()
        slotPath.lineWidth = 0.6
        slotPath.stroke()
        drawText(
            String(format: "%02d", slot.index),
            in: NSRect(x: slotRect.minX, y: slotRect.minY + 5, width: slotRect.width, height: 15),
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.78),
            alignment: .center
        )

        let stateText = statusTitle(for: slot.state, assigned: assigned, transient: transient)
        drawText(
            stateText,
            in: NSRect(x: 84, y: 14, width: bounds.width - 102, height: 16),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: accent,
            letterSpacing: 0.1
        )

        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 18, y: 40))
        divider.line(to: NSPoint(x: bounds.width - 18, y: 40))
        NSColor.white.withAlphaComponent(0.10).setStroke()
        divider.lineWidth = 0.6
        divider.stroke()

        drawText(
            detailText,
            in: NSRect(x: 18, y: 51, width: bounds.width - 36, height: 50),
            font: .systemFont(ofSize: 14.2, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.92),
            lineBreakMode: .byCharWrapping,
            truncates: true,
            maximumLineHeight: 20
        )
    }

    private var detailText: String {
        if let latestMessage = slot.latestMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latestMessage.isEmpty {
            return latestMessage
        }
        return switch slot.state {
        case .off: "这个灯位目前没有分配任务"
        case .idle: "任务空闲，等待下一次运行"
        case .thinking: "Codex 正在处理这个任务"
        case .complete: "任务已完成，打开后会标记为已读"
        case .needsInput: "任务正在等待你的确认或输入"
        case .error: "任务遇到错误，需要检查"
        }
    }

    private func updateContent() {
        let assigned = slot.thread != nil
        let accent = stateColor(slot.state, assigned: assigned)
        statusDot.layer?.backgroundColor = accent.cgColor
        statusDot.layer?.shadowColor = accent.cgColor
        titleLabel.stringValue = slot.thread?.title ?? "未分配任务"
        projectLabel.stringValue = projectName
        statusLabel.stringValue = String(format: "%02d", slot.index)
            + " · "
            + statusTitle(for: slot.state, assigned: assigned, transient: transient)
        statusLabel.textColor = accent
        messageLabel.stringValue = detailText
        updateBorder()
        needsLayout = true
    }

    private var projectName: String {
        guard let cwd = slot.thread?.cwd, !cwd.isEmpty else { return "没有项目" }
        let name = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
        return name.isEmpty ? cwd : name
    }

    private func updateBorder() {
        layer?.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.42 : 0.24).cgColor
        layer?.borderWidth = hovered ? 1.1 : 0.7
    }

    private func statusTitle(for state: AgentState, assigned: Bool, transient: Bool) -> String {
        guard assigned else { return "未分配" }
        if transient {
            return switch state {
            case .complete: "刚刚完成"
            case .needsInput: "需要操作"
            case .error: "发生错误"
            default: statusTitle(for: state, assigned: assigned, transient: false)
            }
        }
        return switch state {
        case .off: "未激活"
        case .idle: "空闲"
        case .thinking: "运行中"
        case .complete: "已完成"
        case .needsInput: "等待输入"
        case .error: "错误"
        }
    }

    private func stateColor(_ state: AgentState, assigned: Bool) -> NSColor {
        guard assigned else { return NSColor(calibratedWhite: 0.48, alpha: 1) }
        return switch state {
        case .off: NSColor(calibratedWhite: 0.58, alpha: 1)
        case .idle: NSColor(calibratedWhite: 0.96, alpha: 1)
        case .thinking: NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.00, alpha: 1)
        case .complete: NSColor(calibratedRed: 0.32, green: 1.00, blue: 0.58, alpha: 1)
        case .needsInput: NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.34, alpha: 1)
        case .error: NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        letterSpacing: CGFloat = 0,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail,
        truncates: Bool = true,
        maximumLineHeight: CGFloat? = nil
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        paragraph.maximumLineHeight = maximumLineHeight ?? rect.height
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: letterSpacing
            ]
        )
        let options: NSString.DrawingOptions = truncates
            ? [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            : [.usesLineFragmentOrigin]
        attributed.draw(with: rect, options: options)
    }

    private func updateAccessibilityLabel() {
        let assigned = slot.thread != nil
        let state = statusTitle(for: slot.state, assigned: assigned, transient: transient)
        setAccessibilityLabel(
            "任务槽位 \(slot.index)，\(state)，"
                + "\(slot.thread?.title ?? "未分配任务")，"
                + "项目 \(projectName)，\(detailText)"
        )
    }
}
