import AppKit
import OSLog
import TourBoxCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum RefreshPolicy {
        static let threadInterval: TimeInterval = 5
        static let rolloutInterval: TimeInterval = 15
        static let timerTolerance: TimeInterval = 1
    }

    private enum StatusPolicy {
        static let permissionDebounce: Duration = .milliseconds(750)
    }

    private let repository = ThreadRepository()
    private let statusStore = StatusStore()
    private let codexController = CodexController()
    private let lifecycleLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yi.tourboxmicro",
        category: "lifecycle"
    )
    private var hudStyle = PreferencesStore.loadHUDStyle()
    private var hudVisible = PreferencesStore.loadHUDVisible()
    private var hudHoverDetailsEnabled = PreferencesStore.loadHUDHoverDetails()
    private var hudStatusNotificationsEnabled = PreferencesStore.loadHUDStatusNotifications()
    private var hudAnimationsEnabled = PreferencesStore.loadHUDAnimations()
    private var hudController: HUDController?
    private var mappingConfiguration = PreferencesStore.loadMapping()
    private lazy var router = InputRouter(configuration: mappingConfiguration)
    private var slotMode = PreferencesStore.loadSlotMode()
    private var resolver = SlotResolver(slotCount: 6)
    private let rolloutChangeMonitor = RolloutChangeMonitor(maximumThreads: 120)
    private let rolloutReconciler = RolloutStateReconciler(maximumThreads: 120)
    private let rolloutPresentationReader = RolloutPresentationReader(maximumThreads: 120)
    private var latestRolloutMessages: [String: String] = [:]
    private var slots: [AgentSlot] = (1...6).map { AgentSlot(index: $0, thread: nil, state: .off) }
    private var recentThreads: [CodexThread] = []
    private var activeSlotIndex: Int?
    private var tourBoxConnected = false
    private var tourBoxServerListening = false
    private var hookServerListening = false
    private var runtimeConnectionState = RuntimeConnectionState()
    private var hookSignalGate = HookSignalGate()
    private var deferredInputTasks: [String: DeferredInputTask] = [:]
    private var refreshTimer: Timer?
    private var threadRefreshInFlight = false
    private var threadRefreshPending = false
    private var didStartRolloutReconciliation = false
    private var rolloutReconciliationInFlight = false
    private var lastRolloutReconciliationAt: Date?
    private var tourBoxServer: TourBoxServer?
    private var hookServer: HookServer?
    private var statusItem: NSStatusItem?
    private var connectionMenuItem: NSMenuItem?
    private var hudMenuItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private var lastHUDRenderState: HUDRenderState?

    private var connectionStatus: String {
        runtimeConnectionState.displayText
    }

    private struct HUDRenderState: Equatable {
        let slots: [AgentSlot]
        let selectedSlotIndex: Int?
        let tourBoxConnected: Bool
        let statusText: String
    }

    private struct DeferredInputTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenuBar()
        if hudVisible {
            makeHUDIfNeeded().show()
        }
        updateHUDMenuTitle()
        startServers()
        refreshThreads()
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
        let refreshTimer = Timer(timeInterval: RefreshPolicy.threadInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshThreads() }
        }
        refreshTimer.tolerance = RefreshPolicy.timerTolerance
        RunLoop.main.add(refreshTimer, forMode: .common)
        self.refreshTimer = refreshTimer
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { openSettings() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        deferredInputTasks.values.forEach { $0.task.cancel() }
        deferredInputTasks.removeAll()
        hookSignalGate.removeAll()
        tourBoxServer?.stop()
        hookServer?.stop()
        hudController?.hide()
        codexController.releaseHeldKeys()
    }

    private func startServers() {
        let tourBoxServer = TourBoxServer(
            onEvent: { [weak self] event in self?.handle(event) },
            onConnection: { [weak self] connected, error in
                self?.tourBoxConnected = connected
                self?.runtimeConnectionState.setTourBoxStatus(
                    error.map { "TourBox：\($0)" }
                        ?? (connected ? "TourBox 已连接" : "等待 TourBox")
                )
                self?.render()
            }
        )
        self.tourBoxServer = tourBoxServer
        do {
            try tourBoxServer.start()
            tourBoxServerListening = true
        } catch {
            tourBoxServerListening = false
            runtimeConnectionState.setTourBoxStatus("Port 50500: \(error.localizedDescription)")
        }

        let hookServer = HookServer(
            onSignal: { [weak self] signal in
                self?.receiveHookSignal(signal)
            },
            onError: { [weak self] error in
                self?.runtimeConnectionState.setHookServerError("Hook server: \(error)")
                self?.render()
            }
        )
        self.hookServer = hookServer
        do {
            try hookServer.start()
            hookServerListening = true
        } catch {
            hookServerListening = false
            runtimeConnectionState.setHookServerError("Port 50501: \(error.localizedDescription)")
        }
        render()
    }

    private func receiveHookSignal(_ signal: HookSignal) {
        switch hookSignalGate.receive(signal) {
        case .deferInput(let identityKey):
            deferredInputTasks.removeValue(forKey: identityKey)?.task.cancel()
            let token = UUID()
            lifecycleLogger.info(
                "Deferring permission signal identity=\(identityKey, privacy: .private(mask: .hash))"
            )
            let task = Task { [weak self] in
                do {
                    try await Task.sleep(for: StatusPolicy.permissionDebounce)
                } catch {
                    return
                }
                guard let self,
                      deferredInputTasks[identityKey]?.token == token else { return }
                deferredInputTasks[identityKey] = nil
                guard let deferred = hookSignalGate.flushDeferredInput(for: identityKey) else {
                    return
                }
                lifecycleLogger.notice(
                    "Committing user-input state identity=\(identityKey, privacy: .private(mask: .hash))"
                )
                applyHookSignal(deferred)
            }
            deferredInputTasks[identityKey] = DeferredInputTask(token: token, task: task)
        case .apply(let current, let canceledIdentityKey):
            if let canceledIdentityKey {
                deferredInputTasks.removeValue(forKey: canceledIdentityKey)?.task.cancel()
                lifecycleLogger.notice(
                    "Canceled permission signal after state=\(current.state.rawValue, privacy: .public) identity=\(canceledIdentityKey, privacy: .private(mask: .hash))"
                )
            }
            applyHookSignal(current)
        }
    }

    private func applyHookSignal(_ signal: HookSignal) {
        statusStore.apply(signal)
        resolveSlots()
    }

    private func refreshThreads() {
        guard !threadRefreshInFlight else {
            threadRefreshPending = true
            return
        }
        threadRefreshInFlight = true
        let repository = repository

        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    return (
                        threads: Optional(try repository.loadRecentThreads(limit: 200)),
                        error: nil as String?
                    )
                } catch {
                    return (threads: nil, error: error.localizedDescription)
                }
            }.value
            guard let self else { return }
            threadRefreshInFlight = false

            if let threads = result.threads {
                let recoveredFromError = runtimeConnectionState.clearCodexStateError()
                if recoveredFromError {
                    lifecycleLogger.notice("Codex state database access recovered")
                }
                if threads != recentThreads {
                    recentThreads = threads
                    resolveSlots()
                } else if recoveredFromError {
                    render()
                }
                startRolloutReconciliationIfNeeded()
            } else if let error = result.error {
                let message = "Codex state: \(error)"
                if runtimeConnectionState.codexStateError != message {
                    runtimeConnectionState.setCodexStateError(message)
                    lifecycleLogger.error("Codex state database refresh failed")
                    render()
                }
            }

            if threadRefreshPending {
                threadRefreshPending = false
                refreshThreads()
            }
        }
    }

    private func startRolloutReconciliationIfNeeded() {
        guard !rolloutReconciliationInFlight else { return }
        let force = !didStartRolloutReconciliation
        if !force,
           let lastRolloutReconciliationAt,
           Date().timeIntervalSince(lastRolloutReconciliationAt) < RefreshPolicy.rolloutInterval {
            return
        }
        didStartRolloutReconciliation = true
        rolloutReconciliationInFlight = true
        lastRolloutReconciliationAt = Date()
        let threads = recentThreads
        let changeMonitor = rolloutChangeMonitor
        let reconciler = rolloutReconciler
        let presentationReader = rolloutPresentationReader
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                let changedThreads = changeMonitor.changedThreads(for: threads, force: force)
                let lifecycle = reconciler.snapshots(for: changedThreads)
                let presentation = presentationReader.snapshots(for: changedThreads)
                return (lifecycle, presentation)
            }.value
            guard let self else { return }
            rolloutReconciliationInFlight = false
            let previousActivities = statusStore.activities
            statusStore.reconcile(result.0)
            var presentationChanged = false
            for snapshot in result.1 {
                if latestRolloutMessages[snapshot.threadID] != snapshot.latestMessage {
                    latestRolloutMessages[snapshot.threadID] = snapshot.latestMessage
                    presentationChanged = true
                }
            }
            if previousActivities != statusStore.activities || presentationChanged {
                resolveSlots()
            }
        }
    }

    private func resolveSlots() {
        let resolvedSlots = resolver.resolve(
            threads: recentThreads,
            activities: statusStore.activities,
            mode: slotMode
        ).map { slot in
            AgentSlot(
                index: slot.index,
                thread: slot.thread,
                state: slot.state,
                detail: slot.detail,
                latestMessage: slot.thread.flatMap { latestRolloutMessages[$0.id] }
            )
        }
        guard resolvedSlots != slots else { return }
        slots = resolvedSlots
        render()
    }

    private func handle(_ event: TourBoxEvent) {
        for action in router.route(event) {
            handle(action)
        }
    }

    private func handle(_ action: MicroAction) {
        switch action {
        case .openSlot(let index):
            openSlot(index)
        case .previousChat:
            cycleSlot(direction: -1)
        case .nextChat:
            cycleSlot(direction: 1)
        case .toggleHUD:
            setHUDVisible(!hudVisible)
        default:
            codexController.perform(action)
        }
    }

    private func openSlot(_ index: Int) {
        guard let slot = slots.first(where: { $0.index == index }), let thread = slot.thread else {
            NSSound.beep()
            return
        }
        activeSlotIndex = index
        statusStore.acknowledge(thread)
        codexController.openThread(thread)
        resolveSlots()
    }

    private func cycleSlot(direction: Int) {
        let assigned = slots.filter { $0.thread != nil }.map(\.index)
        guard !assigned.isEmpty else { return }
        let currentPosition = activeSlotIndex.flatMap { assigned.firstIndex(of: $0) } ?? (direction > 0 ? -1 : 0)
        let nextPosition = (currentPosition + direction + assigned.count) % assigned.count
        openSlot(assigned[nextPosition])
    }

    private func render() {
        let hudState = HUDRenderState(
            slots: slots,
            selectedSlotIndex: activeSlotIndex,
            tourBoxConnected: tourBoxConnected,
            statusText: connectionStatus
        )
        if hudVisible, hudState != lastHUDRenderState {
            makeHUDIfNeeded().update(
                slots: hudState.slots,
                selectedSlotIndex: hudState.selectedSlotIndex,
                tourBoxConnected: hudState.tourBoxConnected,
                statusText: hudState.statusText
            )
            lastHUDRenderState = hudState
        }
        if connectionMenuItem?.title != connectionStatus {
            connectionMenuItem?.title = connectionStatus
        }
        if let controller = settingsWindowController,
           controller.window?.isVisible == true {
            updateSettingsModel(controller.model)
        }
    }

    private func updateSettingsModel(_ model: SettingsModel) {
        model.updateRuntime(
            tourBoxConnected: tourBoxConnected,
            connectionStatus: connectionStatus,
            assignedSlotCount: slots.filter { $0.thread != nil }.count,
            hudVisible: hudVisible,
            tourBoxServerListening: tourBoxServerListening,
            hookServerListening: hookServerListening,
            statusPersistenceReady: statusStore.persistenceAvailable,
            statusPersistenceDetail: statusStore.persistenceDetail
        )
    }

    private func makeHUDIfNeeded() -> HUDController {
        if let hudController { return hudController }
        let controller = HUDController(
            style: hudStyle,
            hoverDetailsEnabled: hudHoverDetailsEnabled,
            statusNotificationsEnabled: hudStatusNotificationsEnabled,
            animationsEnabled: hudAnimationsEnabled
        )
        controller.onOpenSlot = { [weak self] index in self?.openSlot(index) }
        hudController = controller
        return controller
    }

    private func configureMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        let menuBarImage = NSImage(
            systemSymbolName: "dial.medium",
            accessibilityDescription: "TourBox Micro"
        )
        menuBarImage?.isTemplate = true
        statusItem.button?.image = menuBarImage
        statusItem.button?.contentTintColor = nil

        let menu = NSMenu()
        let connectionItem = NSMenuItem(title: connectionStatus, action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        connectionMenuItem = connectionItem
        menu.addItem(connectionItem)
        menu.addItem(.separator())

        let hudItem = NSMenuItem(title: "隐藏六任务 HUD", action: #selector(toggleHUD), keyEquivalent: "h")
        hudItem.target = self
        hudMenuItem = hudItem
        menu.addItem(hudItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let resetHUDItem = NSMenuItem(title: "重置 HUD 尺寸与位置", action: #selector(resetHUD), keyEquivalent: "")
        resetHUDItem.target = self
        menu.addItem(resetHUDItem)

        let openItem = NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let integrationItem = NSMenuItem(title: "安装 Codex Hooks 与基础快捷键…", action: #selector(installIntegration), keyEquivalent: "")
        integrationItem.target = self
        menu.addItem(integrationItem)

        let accessibilityItem = NSMenuItem(title: "授予辅助功能权限…", action: #selector(requestAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 TourBox Micro", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateHUDMenuTitle() {
        hudMenuItem?.title = hudVisible ? "隐藏六任务 HUD" : "显示六任务 HUD"
    }

    @objc private func toggleHUD() {
        setHUDVisible(!hudVisible)
    }

    private func setHUDVisible(_ visible: Bool) {
        guard visible != hudVisible else { return }
        hudVisible = visible
        if visible {
            lastHUDRenderState = nil
            let controller = makeHUDIfNeeded()
            render()
            controller.show()
        } else {
            hudController?.close()
            hudController = nil
            lastHUDRenderState = nil
        }
        PreferencesStore.saveHUDVisible(visible)
        updateHUDMenuTitle()
        render()
    }

    @objc private func resetHUD() {
        hudVisible = true
        lastHUDRenderState = nil
        let controller = makeHUDIfNeeded()
        render()
        controller.resetPosition()
        PreferencesStore.saveHUDVisible(true)
        updateHUDMenuTitle()
        render()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let callbacks = SettingsCallbacks(
                setHUDVisible: { [weak self] visible in
                    self?.setHUDVisible(visible)
                },
                setHUDStyle: { [weak self] style in
                    guard let self else { return }
                    guard style != self.hudStyle else { return }
                    self.hudStyle = style
                    PreferencesStore.saveHUDStyle(style)
                    self.hudController?.setStyle(style)
                    self.lastHUDRenderState = nil
                    self.render()
                },
                setHUDHoverDetails: { [weak self] enabled in
                    guard let self else { return }
                    guard enabled != self.hudHoverDetailsEnabled else { return }
                    self.hudHoverDetailsEnabled = enabled
                    PreferencesStore.saveHUDHoverDetails(enabled)
                    self.hudController?.setHoverDetailsEnabled(enabled)
                },
                setHUDStatusNotifications: { [weak self] enabled in
                    guard let self else { return }
                    guard enabled != self.hudStatusNotificationsEnabled else { return }
                    self.hudStatusNotificationsEnabled = enabled
                    PreferencesStore.saveHUDStatusNotifications(enabled)
                    self.hudController?.setStatusNotificationsEnabled(enabled)
                },
                setHUDAnimations: { [weak self] enabled in
                    guard let self else { return }
                    guard enabled != self.hudAnimationsEnabled else { return }
                    self.hudAnimationsEnabled = enabled
                    PreferencesStore.saveHUDAnimations(enabled)
                    self.hudController?.setAnimationsEnabled(enabled)
                },
                setSlotMode: { [weak self] mode in
                    guard let self else { return }
                    guard mode != self.slotMode else { return }
                    self.slotMode = mode
                    PreferencesStore.saveSlotMode(mode)
                    self.resolveSlots()
                },
                setMapping: { [weak self] mapping in
                    guard let self else { return }
                    self.mappingConfiguration = mapping
                    self.router.updateConfiguration(mapping)
                    PreferencesStore.saveMapping(mapping)
                },
                openCodex: { [weak self] in self?.codexController.openCodex() },
                installIntegration: { [weak self] in
                    guard let self else { return "App 正在退出。" }
                    return try self.performInstallIntegration()
                },
                requestAccessibility: { [weak self] in self?.codexController.requestAccessibilityAccess() }
            )
            let model = SettingsModel(
                hudVisible: hudVisible,
                hudStyle: hudStyle,
                hudHoverDetailsEnabled: hudHoverDetailsEnabled,
                hudStatusNotificationsEnabled: hudStatusNotificationsEnabled,
                hudAnimationsEnabled: hudAnimationsEnabled,
                slotMode: slotMode,
                mapping: mappingConfiguration,
                callbacks: callbacks
            )
            settingsWindowController = SettingsWindowController(model: model) { [weak self] in
                self?.settingsWindowController = nil
            }
        }
        if let model = settingsWindowController?.model {
            updateSettingsModel(model)
        }
        settingsWindowController?.show()
    }

    @objc private func openCodex() {
        codexController.openCodex()
    }

    @objc private func requestAccessibility() {
        codexController.requestAccessibilityAccess()
    }

    @objc private func installIntegration() {
        do {
            showAlert(
                title: "Codex integration installed",
                message: try performInstallIntegration()
            )
        } catch {
            showAlert(title: "Installation failed", message: error.localizedDescription)
        }
    }

    private func performInstallIntegration() throws -> String {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let hooks = try ConfigurationInstaller.installHooks(at: codexDirectory.appendingPathComponent("hooks.json"))
        let keys = try ConfigurationInstaller.installKeybindings(at: codexDirectory.appendingPathComponent("keybindings.json"))
        let backups = [hooks.backupPath, keys.backupPath].compactMap { $0 }
        let backupText = backups.isEmpty ? "本次无需创建备份。" : "备份：\n\(backups.joined(separator: "\n"))"
        return """
        Hooks 与基础快捷键已安装，现有设置已保留。重启 Codex，并在提示时检查并信任 Hooks。

        推理旋钮需要人工绑定一次：
        1. 打开 Codex 设置 → 键盘快捷键
        2. 搜索“推理”或“effort”
        3. 录制“增加推理强度”时向右转旋钮一格（F16）
        4. 录制“降低推理强度”时向左转旋钮一格（F17）

        \(backupText)
        """
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
