import Foundation

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case off
    case idle
    case thinking
    case complete
    case needsInput
    case error
}

public struct CodexThread: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let cwd: String
    public let preview: String
    public let recencyAtMilliseconds: Int64
    public let isPinned: Bool
    public let rolloutPath: String?

    public init(
        id: String,
        title: String,
        cwd: String,
        preview: String = "",
        recencyAtMilliseconds: Int64,
        isPinned: Bool = false,
        rolloutPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.preview = preview
        self.recencyAtMilliseconds = recencyAtMilliseconds
        self.isPinned = isPinned
        self.rolloutPath = rolloutPath
    }
}

public struct AgentActivity: Equatable, Sendable {
    public let threadID: String?
    public let cwd: String?
    public let state: AgentState
    public let updatedAt: Date
    public let detail: String?

    public init(
        threadID: String? = nil,
        cwd: String? = nil,
        state: AgentState,
        updatedAt: Date = Date(),
        detail: String? = nil
    ) {
        self.threadID = threadID
        self.cwd = cwd
        self.state = state
        self.updatedAt = updatedAt
        self.detail = detail
    }
}

public struct AgentSlot: Equatable, Identifiable, Sendable {
    public let index: Int
    public let thread: CodexThread?
    public let state: AgentState
    public let detail: String?
    public let latestMessage: String?

    public var id: Int { index }

    public init(
        index: Int,
        thread: CodexThread?,
        state: AgentState,
        detail: String? = nil,
        latestMessage: String? = nil
    ) {
        self.index = index
        self.thread = thread
        self.state = state
        self.detail = detail
        self.latestMessage = latestMessage
    }
}

public enum SlotMode: String, Codable, CaseIterable, Hashable, Sendable {
    case recent
    case priority
    case pinned
}
