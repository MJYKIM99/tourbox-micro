import AppKit
import ApplicationServices
import SwiftUI
import TourBoxCore

@MainActor
struct SettingsCallbacks {
    let setHUDVisible: (Bool) -> Void
    let setHUDStyle: (HUDStyle) -> Void
    let setHUDHoverDetails: (Bool) -> Void
    let setHUDStatusNotifications: (Bool) -> Void
    let setHUDAnimations: (Bool) -> Void
    let setSlotMode: (SlotMode) -> Void
    let setMapping: (InputMappingConfiguration) -> Void
    let openCodex: () -> Void
    let installIntegration: () throws -> String
    let requestAccessibility: () -> Void
}

@MainActor
final class SettingsModel: ObservableObject {
    struct DiagnosticItem: Identifiable, Equatable {
        enum State: Equatable {
            case ready
            case actionRequired
            case inactive
        }

        let id: String
        let title: String
        let detail: String
        let symbol: String
        let state: State
    }

    private struct RuntimeState: Equatable {
        var tourBoxConnected = false
        var connectionStatus = "等待 TourBox"
        var assignedSlotCount = 0
        var tourBoxServerListening = false
        var hookServerListening = false
        var statusPersistenceReady = false
        var statusPersistenceDetail = "等待状态数据库"
    }

    private struct SystemDiagnosticState: Equatable {
        var codexFound = false
        var databaseFound = false
        var accessibilityTrusted = false
        var hooksInstalled = false
        var keysInstalled = false
        var reasoningKeysInstalled = false
    }

    @Published var hudVisible: Bool
    @Published var hudStyle: HUDStyle
    @Published var hudHoverDetailsEnabled: Bool
    @Published var hudStatusNotificationsEnabled: Bool
    @Published var hudAnimationsEnabled: Bool
    @Published var slotMode: SlotMode
    @Published var mapping: InputMappingConfiguration
    @Published private var runtime = RuntimeState()
    @Published var loginEnabled = false
    @Published var loginStatus = "正在检查"
    @Published var diagnostics: [DiagnosticItem] = []
    @Published var noticeTitle = ""
    @Published var noticeMessage = ""
    @Published var showingNotice = false

    var blockingIssueCount: Int {
        diagnostics.filter { $0.state == .actionRequired }.count
    }

    var systemReady: Bool { blockingIssueCount == 0 }

    var tourBoxConnected: Bool { runtime.tourBoxConnected }
    var connectionStatus: String { runtime.connectionStatus }
    var assignedSlotCount: Int { runtime.assignedSlotCount }
    var tourBoxServerListening: Bool { runtime.tourBoxServerListening }
    var hookServerListening: Bool { runtime.hookServerListening }
    var statusPersistenceReady: Bool { runtime.statusPersistenceReady }
    var statusPersistenceDetail: String { runtime.statusPersistenceDetail }

    private let callbacks: SettingsCallbacks
    private var systemDiagnostics = SystemDiagnosticState()

    init(
        hudVisible: Bool,
        hudStyle: HUDStyle,
        hudHoverDetailsEnabled: Bool,
        hudStatusNotificationsEnabled: Bool,
        hudAnimationsEnabled: Bool,
        slotMode: SlotMode,
        mapping: InputMappingConfiguration,
        callbacks: SettingsCallbacks
    ) {
        self.hudVisible = hudVisible
        self.hudStyle = hudStyle
        self.hudHoverDetailsEnabled = hudHoverDetailsEnabled
        self.hudStatusNotificationsEnabled = hudStatusNotificationsEnabled
        self.hudAnimationsEnabled = hudAnimationsEnabled
        self.slotMode = slotMode
        self.mapping = mapping
        self.callbacks = callbacks
    }

    func updateRuntime(
        tourBoxConnected: Bool,
        connectionStatus: String,
        assignedSlotCount: Int,
        hudVisible: Bool,
        tourBoxServerListening: Bool,
        hookServerListening: Bool,
        statusPersistenceReady: Bool,
        statusPersistenceDetail: String
    ) {
        let nextRuntime = RuntimeState(
            tourBoxConnected: tourBoxConnected,
            connectionStatus: connectionStatus,
            assignedSlotCount: assignedSlotCount,
            tourBoxServerListening: tourBoxServerListening,
            hookServerListening: hookServerListening,
            statusPersistenceReady: statusPersistenceReady,
            statusPersistenceDetail: statusPersistenceDetail
        )
        var changed = false
        if runtime != nextRuntime {
            runtime = nextRuntime
            changed = true
        }
        if self.hudVisible != hudVisible {
            self.hudVisible = hudVisible
            changed = true
        }
        if changed { rebuildDiagnostics() }
    }

    func setHUDVisible(_ visible: Bool) {
        guard hudVisible != visible else { return }
        hudVisible = visible
        callbacks.setHUDVisible(visible)
    }

    func setHUDStyle(_ style: HUDStyle) {
        guard hudStyle != style else { return }
        hudStyle = style
        callbacks.setHUDStyle(style)
    }

    func setHUDHoverDetails(_ enabled: Bool) {
        guard hudHoverDetailsEnabled != enabled else { return }
        hudHoverDetailsEnabled = enabled
        callbacks.setHUDHoverDetails(enabled)
    }

    func setHUDStatusNotifications(_ enabled: Bool) {
        guard hudStatusNotificationsEnabled != enabled else { return }
        hudStatusNotificationsEnabled = enabled
        callbacks.setHUDStatusNotifications(enabled)
    }

    func setHUDAnimations(_ enabled: Bool) {
        guard hudAnimationsEnabled != enabled else { return }
        hudAnimationsEnabled = enabled
        callbacks.setHUDAnimations(enabled)
    }

    func setSlotMode(_ mode: SlotMode) {
        guard slotMode != mode else { return }
        slotMode = mode
        callbacks.setSlotMode(mode)
    }

    func setAction(_ action: ButtonAction, for control: TourBoxControl) {
        guard mapping.action(for: control) != action else { return }
        mapping.set(action, for: control)
        callbacks.setMapping(mapping)
    }

    func resetMapping() {
        guard mapping != .default else { return }
        mapping = .default
        callbacks.setMapping(mapping)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
        } catch {
            showNotice(title: "登录启动设置失败", message: error.localizedDescription)
        }
        refreshDiagnostics()
    }

    func installIntegration() {
        do {
            showNotice(title: "Codex 集成已安装", message: try callbacks.installIntegration())
        } catch {
            showNotice(title: "安装失败", message: error.localizedDescription)
        }
        refreshDiagnostics()
    }

    func requestAccessibility() {
        callbacks.requestAccessibility()
        refreshDiagnostics()
    }

    func openCodex() {
        callbacks.openCodex()
    }

    func refreshDiagnostics() {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let hooksText = (try? String(contentsOf: codexDirectory.appendingPathComponent("hooks.json"), encoding: .utf8)) ?? ""
        let keybindingsURL = codexDirectory.appendingPathComponent("keybindings.json")
        systemDiagnostics = SystemDiagnosticState(
            codexFound: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil,
            databaseFound: FileManager.default.fileExists(atPath: codexDirectory.appendingPathComponent("state_5.sqlite").path),
            accessibilityTrusted: AXIsProcessTrusted(),
            hooksInstalled: hooksText.contains(ConfigurationInstaller.hookMarker),
            keysInstalled: ConfigurationInstaller.managedKeybindingsInstalled(at: keybindingsURL),
            reasoningKeysInstalled: ConfigurationInstaller.manualReasoningKeybindingsInstalled(at: keybindingsURL)
        )
        let loginSnapshot = LoginItemManager.snapshot()
        if loginEnabled != loginSnapshot.isEnabled { loginEnabled = loginSnapshot.isEnabled }
        if loginStatus != loginSnapshot.statusDescription { loginStatus = loginSnapshot.statusDescription }
        rebuildDiagnostics()
    }

    private func rebuildDiagnostics() {
        let nextDiagnostics: [DiagnosticItem] = [
            .init(
                id: "tourbox",
                title: "TourBox 输入",
                detail: connectionStatus,
                symbol: "dial.medium",
                state: tourBoxConnected ? .ready : .actionRequired
            ),
            .init(
                id: "ports",
                title: "本地服务",
                detail: "输入 127.0.0.1:50500 · Hooks 127.0.0.1:50501",
                symbol: "network",
                state: tourBoxServerListening && hookServerListening ? .ready : .actionRequired
            ),
            .init(
                id: "codex",
                title: "Codex 桌面 App",
                detail: systemDiagnostics.codexFound ? "已找到" : "未找到",
                symbol: "app.badge.checkmark",
                state: systemDiagnostics.codexFound ? .ready : .actionRequired
            ),
            .init(
                id: "database",
                title: "六任务索引",
                detail: systemDiagnostics.databaseFound ? "state_5.sqlite 可读" : "状态数据库缺失",
                symbol: "square.stack.3d.up",
                state: systemDiagnostics.databaseFound ? .ready : .actionRequired
            ),
            .init(
                id: "status-database",
                title: "任务状态持久化",
                detail: statusPersistenceDetail,
                symbol: "externaldrive.badge.checkmark",
                state: statusPersistenceReady ? .ready : .actionRequired
            ),
            .init(
                id: "hooks",
                title: "生命周期 Hooks",
                detail: systemDiagnostics.hooksInstalled ? "4 个 Hook 已安装" : "尚未安装",
                symbol: "point.3.connected.trianglepath.dotted",
                state: systemDiagnostics.hooksInstalled ? .ready : .actionRequired
            ),
            .init(
                id: "keys",
                title: "基础快捷键",
                detail: systemDiagnostics.keysInstalled ? "F13 · F14 · F15 已安装" : "自动映射不完整",
                symbol: "keyboard",
                state: systemDiagnostics.keysInstalled ? .ready : .actionRequired
            ),
            .init(
                id: "reasoning-keys",
                title: "推理旋钮",
                detail: systemDiagnostics.reasoningKeysInstalled ? "F16 增加 · F17 降低" : "Codex 录制时：右转=F16 · 左转=F17",
                symbol: "dial.medium",
                state: systemDiagnostics.reasoningKeysInstalled ? .ready : .actionRequired
            ),
            .init(
                id: "accessibility",
                title: "辅助功能权限",
                detail: systemDiagnostics.accessibilityTrusted ? "已授权" : "需要授权",
                symbol: "hand.raised",
                state: systemDiagnostics.accessibilityTrusted ? .ready : .actionRequired
            ),
            .init(
                id: "login",
                title: "登录时启动",
                detail: loginStatus,
                symbol: "power",
                state: loginEnabled ? .ready : .inactive
            )
        ]
        if diagnostics != nextDiagnostics { diagnostics = nextDiagnostics }
    }

    private func showNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
