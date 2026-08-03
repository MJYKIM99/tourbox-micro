import Foundation

public enum ButtonAction: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case toggleFast
    case togglePlan
    case forkThread
    case approveOrSend
    case rejectOrCancel
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
    case searchChats
    case jumpToLatest
    case previousChat
    case nextChat
    case navigateBack
    case navigateForward
    case toggleSidebar

    public var microAction: MicroAction? {
        switch self {
        case .none: nil
        case .toggleFast: .toggleFast
        case .togglePlan: .togglePlan
        case .forkThread: .forkThread
        case .approveOrSend: .approveOrSend
        case .rejectOrCancel: .rejectOrCancel
        case .openReview: .openReview
        case .openModelPicker: .openModelPicker
        case .quickChat: .quickChat
        case .findInChat: .findInChat
        case .openCommandMenu: .openCommandMenu
        case .searchFiles: .searchFiles
        case .newIndependentChat: .newIndependentChat
        case .copy: .copy
        case .paste: .paste
        case .screenshot: .screenshot
        case .previousRecentChat: .previousRecentChat
        case .nextRecentChat: .nextRecentChat
        case .searchChats: .searchChats
        case .jumpToLatest: .jumpToLatest
        case .previousChat: .previousChat
        case .nextChat: .nextChat
        case .navigateBack: .navigateBack
        case .navigateForward: .navigateForward
        case .toggleSidebar: .toggleSidebar
        }
    }
}

public struct InputMappingConfiguration: Codable, Equatable, Sendable {
    private var actions: [String: ButtonAction]

    public init(actions: [TourBoxControl: ButtonAction] = [:]) {
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.key.rawValue, $0.value) })
    }

    public func action(for control: TourBoxControl) -> ButtonAction? {
        actions[control.rawValue]
    }

    public mutating func set(_ action: ButtonAction, for control: TourBoxControl) {
        actions[control.rawValue] = action
    }

    public static let configurableControls: [TourBoxControl] = [
        .knob, .scroll, .dial,
        .top, .tall, .side,
        .c1, .c2,
        .up, .right, .down, .left
    ]

    public static let `default` = InputMappingConfiguration(actions: [
        .knob: .openModelPicker,
        .scroll: .jumpToLatest,
        .dial: .searchChats,
        .top: .newIndependentChat,
        .tall: .approveOrSend,
        .side: .rejectOrCancel,
        .c1: .copy,
        .c2: .paste,
        .up: .screenshot,
        .right: .nextRecentChat,
        .down: .openReview,
        .left: .previousRecentChat
    ])
}
