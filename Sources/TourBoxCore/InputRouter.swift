import Foundation

public enum MicroAction: Equatable, Sendable {
    case toggleFast
    case togglePlan
    case forkThread
    case approveOrSend
    case rejectOrCancel
    case voice(pressed: Bool)
    case openReview
    case openModelPicker
    case quickChat
    case findInChat
    case openCommandMenu
    case searchFiles
    case newIndependentChat
    case copy
    case paste
    case screenshot
    case previousRecentChat
    case nextRecentChat
    case adjustReasoning(Int)
    case previousChat
    case nextChat
    case searchChats
    case scroll(Int)
    case jumpToLatest
    case navigateBack
    case navigateForward
    case toggleSidebar
    case openSlot(Int)
    case toggleHUD
}

/// Turns raw TourBox input into Codex Micro-style actions.
///
/// The Tour button acts as a layer modifier. Holding it and pressing
/// C1/C2/Up/Right/Down/Left selects agent slots 1...6. Knob/Scroll/Dial/Top
/// trigger a secondary Codex action. Tapping Tour on its own toggles the HUD.
public struct InputRouter: Sendable {
    private var tourHeld = false
    private var tourWasConsumed = false
    private var suppressedReleases: Set<TourBoxControl> = []
    private var configuration: InputMappingConfiguration

    public init(configuration: InputMappingConfiguration = .default) {
        self.configuration = configuration
    }

    public mutating func updateConfiguration(_ configuration: InputMappingConfiguration) {
        self.configuration = configuration
    }

    public mutating func route(_ event: TourBoxEvent) -> [MicroAction] {
        if event.control == .tour {
            return routeTour(event.phase)
        }

        if suppressedReleases.contains(event.control), event.phase == .released {
            suppressedReleases.remove(event.control)
            return []
        }

        if tourHeld, event.phase == .pressed {
            if let slot = Self.slotForLayerControl[event.control] {
                tourWasConsumed = true
                suppressedReleases.insert(event.control)
                return [.openSlot(slot)]
            }
            if let action = Self.actionForLayerControl[event.control] {
                tourWasConsumed = true
                suppressedReleases.insert(event.control)
                return [action]
            }
        }

        return routeBase(event)
    }

    private mutating func routeTour(_ phase: TourBoxPhase) -> [MicroAction] {
        switch phase {
        case .pressed:
            tourHeld = true
            tourWasConsumed = false
            return []
        case .released:
            let shouldToggleHUD = tourHeld && !tourWasConsumed
            tourHeld = false
            tourWasConsumed = false
            return shouldToggleHUD ? [.toggleHUD] : []
        case .step:
            return []
        }
    }

    private func routeBase(_ event: TourBoxEvent) -> [MicroAction] {
        if event.phase == .pressed,
           let action = configuration.action(for: event.control)?.microAction {
            return [action]
        }

        switch (event.control, event.phase) {
        case (.knob, .step(let delta)):
            return [.adjustReasoning(delta)]
        case (.scroll, .step(let delta)):
            return [.scroll(delta)]
        case (.dial, .step(let delta)):
            return [delta > 0 ? .nextChat : .previousChat]
        case (.short, .pressed):
            return [.voice(pressed: true)]
        case (.short, .released):
            return [.voice(pressed: false)]
        default:
            return []
        }
    }

    private static let slotForLayerControl: [TourBoxControl: Int] = [
        .c1: 1,
        .c2: 2,
        .up: 3,
        .right: 4,
        .down: 5,
        .left: 6
    ]

    private static let actionForLayerControl: [TourBoxControl: MicroAction] = [
        .knob: .quickChat,
        .scroll: .findInChat,
        .dial: .openCommandMenu,
        .top: .searchFiles
    ]
}
