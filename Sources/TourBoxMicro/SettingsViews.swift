import AppKit
import SwiftUI
import TourBoxCore

private enum MicroPalette {
    static var ink: Color { Color(red: 0.075, green: 0.075, blue: 0.07) }
    static var graphite: Color { Color(red: 0.28, green: 0.28, blue: 0.26) }
    static var accent: Color { ink }
    static var accentBright: Color { graphite }
    static var cyan: Color { graphite }
    static var card: Color { Color.white.opacity(0.46) }
    static var elevatedCard: Color { Color.white.opacity(0.62) }
    static var page: Color { Color.white.opacity(0.12) }
    static var sidebar: Color { ink.opacity(0.80) }
    static var line: Color { ink.opacity(0.18) }
    static var glassHighlight: Color { Color.white.opacity(0.50) }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case overview
    case controls
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .controls: "控制映射"
        case .diagnostics: "诊断"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "运行方式与集成"
        case .controls: "自定义硬件动作"
        case .diagnostics: "连接与权限状态"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .controls: "slider.horizontal.3"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @State private var selection: SettingsSection = .overview

    var body: some View {
        ZStack {
            GlassEffectView(
                material: .underWindowBackground,
                blendingMode: .behindWindow,
                state: .active,
                emphasized: true
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color(red: 0.76, green: 0.77, blue: 0.73).opacity(0.10),
                    Color.black.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                SettingsSidebar(model: model, selection: $selection)
                    .frame(width: 218)
                    .environment(\.colorScheme, .dark)

                Rectangle()
                    .fill(Color.white.opacity(0.24))
                    .overlay(MicroPalette.ink.opacity(0.16))
                    .frame(width: 1)

                ZStack {
                    MicroPalette.page

                    Group {
                        switch selection {
                        case .overview:
                            OverviewPage(model: model)
                        case .controls:
                            ControlsPage(model: model)
                        case .diagnostics:
                            DiagnosticsPage(model: model)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 840, minHeight: 600)
        .background(Color.clear)
        .tint(MicroPalette.accent)
        .preferredColorScheme(.light)
        .ignoresSafeArea()
        .alert(model.noticeTitle, isPresented: $model.showingNotice) {
            Button("好") {}
        } message: {
            Text(model.noticeMessage)
        }
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    @Binding var selection: SettingsSection

    private var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(value ?? "0.3.0")"
    }

    var body: some View {
        ZStack {
            MicroPalette.sidebar

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .grayscale(1)
                        .contrast(1.25)
                        .frame(width: 40, height: 40)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TourBox Micro")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                        Text("CONTROL UNIT / 01")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 28)

                Text("SYSTEM MENU")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)

                VStack(spacing: 6) {
                    ForEach(SettingsSection.allCases) { section in
                        SidebarButton(
                            section: section,
                            selected: selection == section,
                            badge: section == .diagnostics && model.blockingIssueCount > 0
                                ? model.blockingIssueCount
                                : nil
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) { selection = section }
                        }
                    }
                }

                Spacer()

                SidebarConnectionCard(model: model)

                HStack {
                    Text(version)
                    Spacer()
                    Text("本地运行")
                }
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 44)
            .padding(.bottom, 16)
        }
    }
}

private struct SidebarButton: View {
    let section: SettingsSection
    let selected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? MicroPalette.ink : Color.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            selected ? MicroPalette.ink.opacity(0.09) : Color.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
            }
            .foregroundStyle(selected ? MicroPalette.ink : Color.white.opacity(0.76))
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(
                selected ? Color.white.opacity(0.88) : Color.white.opacity(hovering ? 0.10 : 0),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SidebarConnectionCard: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(model.tourBoxConnected ? 0.95 : 0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.tourBoxConnected ? MicroPalette.ink : Color.white.opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.tourBoxConnected ? "设备在线" : "等待设备")
                        .font(.caption.weight(.semibold))
                    Text(model.tourBoxConnected ? "TourBox 已连接" : model.connectionStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { index in
                    Rectangle()
                        .fill(index < model.assignedSlotCount ? Color.white : Color.white.opacity(0.14))
                        .frame(height: 5)
                }
            }

            HStack {
                Text("任务槽位")
                Spacer()
                Text("\(model.assignedSlotCount) / 6")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct OverviewPage: View {
    @ObservedObject var model: SettingsModel

    private var slotModeDetail: String {
        switch model.slotMode {
        case .priority: "优先处理排序"
        case .recent: "最近使用排序"
        case .pinned: "置顶任务排序"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "TOURBOX × CODEX",
                    title: "总览",
                    subtitle: "让硬件操作与你的 Codex 工作流保持同步。"
                )

                OverviewHero(model: model)

                HStack(spacing: 12) {
                    MetricCard(
                        title: "TourBox",
                        value: model.tourBoxConnected ? "已连接" : "未连接",
                        detail: "TCP 50500",
                        symbol: "dial.medium",
                        color: MicroPalette.ink
                    )
                    MetricCard(
                        title: "任务槽位",
                        value: "\(model.assignedSlotCount) / 6",
                        detail: slotModeDetail,
                        symbol: "square.stack.3d.up",
                        color: MicroPalette.graphite
                    )
                    MetricCard(
                        title: "系统状态",
                        value: model.systemReady ? "全部就绪" : "\(model.blockingIssueCount) 项待处理",
                        detail: model.systemReady ? "集成运行正常" : "前往诊断查看",
                        symbol: model.systemReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        color: model.systemReady ? MicroPalette.ink : MicroPalette.graphite
                    )
                }

                SectionLabel(title: "运行方式", subtitle: "常用显示与启动选项")

                HStack(alignment: .top, spacing: 14) {
                    SurfaceCard {
                        VStack(spacing: 0) {
                            SettingToggleRow(
                                title: "六任务状态 HUD",
                                detail: "在屏幕边缘显示任务进度与提醒",
                                symbol: "rectangle.on.rectangle",
                                isOn: Binding(
                                    get: { model.hudVisible },
                                    set: { model.setHUDVisible($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            VStack(alignment: .leading, spacing: 10) {
                                Label("HUD 显示样式", systemImage: "square.grid.3x2")
                                    .font(.system(size: 13, weight: .semibold))
                                Picker("HUD 显示样式", selection: Binding(
                                    get: { model.hudStyle },
                                    set: { model.setHUDStyle($0) }
                                )) {
                                    Text("玻璃灯阵").tag(HUDStyle.glassLights)
                                    Text("详细列表").tag(HUDStyle.taskList)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                Text(model.hudStyle == .glassLights
                                     ? "六个发光方块固定在左下角，以颜色显示任务状态。"
                                     : "完整显示任务标题、项目和运行状态。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "悬浮任务详情",
                                detail: "指向灯块时显示任务、项目与当前状态",
                                symbol: "cursorarrow.motionlines",
                                isOn: Binding(
                                    get: { model.hudHoverDetailsEnabled },
                                    set: { model.setHUDHoverDetails($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "灯光状态动效",
                                detail: "按任务状态显示呼吸、流光与提醒脉冲",
                                symbol: "sparkles",
                                isOn: Binding(
                                    get: { model.hudAnimationsEnabled },
                                    set: { model.setHUDAnimations($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "状态变化提示",
                                detail: "完成、等待输入或报错时短暂显示任务卡",
                                symbol: "bell.badge",
                                isOn: Binding(
                                    get: { model.hudStatusNotificationsEnabled },
                                    set: { model.setHUDStatusNotifications($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "登录时自动启动",
                                detail: model.loginStatus,
                                symbol: "power",
                                isOn: Binding(
                                    get: { model.loginEnabled },
                                    set: { model.setLaunchAtLogin($0) }
                                )
                            )
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("任务槽位排序", systemImage: "arrow.up.arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                            Text("决定六个硬件槽位优先装入哪些 Codex 任务。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Picker("任务槽位排序", selection: Binding(
                                get: { model.slotMode },
                                set: { model.setSlotMode($0) }
                            )) {
                                Text("优先处理").tag(SlotMode.priority)
                                Text("最近使用").tag(SlotMode.recent)
                                Text("置顶任务").tag(SlotMode.pinned)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SurfaceCard {
                    HStack(spacing: 16) {
                        SymbolTile(symbol: "link.badge.plus", color: MicroPalette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Codex 集成")
                                .font(.system(size: 14, weight: .semibold))
                            Text("自动安装 Hooks 与基础快捷键；推理旋钮由你在 Codex 中人工绑定。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重新安装集成") { model.installIntegration() }
                            .buttonStyle(.bordered)
                        Button("打开 Codex") { model.openCodex() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OverviewHero: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("TBM—01  /  LOCAL BRIDGE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.tourBoxConnected ? Color.white : Color.clear)
                            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                            .frame(width: 7, height: 7)
                        Text(model.tourBoxConnected ? "ONLINE" : "STANDBY")
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.white.opacity(0.7))

                Spacer()

                Text("把 TourBox 变成\nCodex 的实体控制台")
                    .font(.system(size: 24, weight: .black))
                    .tracking(-0.45)
                Text("旋转 / 切换 / 审批 / 任务导航")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.62))
                    .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(MicroPalette.ink.opacity(0.82))

            VStack(spacing: 5) {
                Text("ACTIVE SLOTS")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                Text(String(format: "%02d", model.assignedSlotCount))
                    .font(.system(size: 46, weight: .light, design: .monospaced))
                    .tracking(-3)
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { index in
                        Rectangle()
                            .fill(index < model.assignedSlotCount ? MicroPalette.ink : Color.clear)
                            .frame(width: 12, height: 5)
                            .overlay(Rectangle().stroke(MicroPalette.ink.opacity(0.6), lineWidth: 1))
                    }
                }
                Text("MAX / 06")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background(MicroPalette.elevatedCard)
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MicroPalette.glassHighlight, lineWidth: 1)
        }
    }
}

private struct ControlsPage: View {
    @ObservedObject var model: SettingsModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeader(
                        eyebrow: "HARDWARE MAPPING",
                        title: "控制映射",
                        subtitle: "选择每个实体控件触发的 Codex 或通用动作。"
                    )
                    Spacer()
                    Button("恢复默认") { model.resetMapping() }
                        .buttonStyle(.bordered)
                }

                InfoBanner(
                    symbol: "lock.shield",
                    title: "安全动作保持固定",
                    detail: "Short 按住说话；Tour + C1/C2/方向键选择六任务；Tour + 旋钮/滚轮/转盘/横键触发快速聊天、当前查找、命令菜单和文件搜索。"
                )

                MappingGroupHeader(title: "旋转区", subtitle: "按下动作可自定义；旋转方向用于连续导航")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach([TourBoxControl.knob, .scroll, .dial], id: \.self) { control in
                        MappingTile(model: model, control: control)
                    }
                }

                MappingGroupHeader(title: "控制区", subtitle: "高频操作与确认动作")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach([TourBoxControl.top, .tall, .side, .c1, .c2], id: \.self) { control in
                        MappingTile(model: model, control: control)
                    }
                }

                MappingGroupHeader(title: "方向键", subtitle: "截图、最近聊天切换与审阅")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach([TourBoxControl.up, .right, .down, .left], id: \.self) { control in
                        MappingTile(model: model, control: control)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MappingTile: View {
    @ObservedObject var model: SettingsModel
    let control: TourBoxControl

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: control.settingsSymbol, color: control.settingsColor, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(control.settingsName)
                    .font(.system(size: 13, weight: .semibold))
                Text(control.settingsHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Picker(control.settingsName, selection: Binding(
                get: { model.mapping.action(for: control) ?? .none },
                set: { model.setAction($0, for: control) }
            )) {
                ForEach(ButtonAction.allCases, id: \.self) { action in
                    Label(action.settingsName, systemImage: action.settingsSymbol).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 158)
        }
        .padding(13)
        .background(MicroPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MicroPalette.line, lineWidth: 1)
        }
    }
}

private struct DiagnosticsPage: View {
    @ObservedObject var model: SettingsModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeader(
                        eyebrow: "SYSTEM HEALTH",
                        title: "诊断",
                        subtitle: "检查从 TourBox 输入到 Codex 动作的完整本地链路。"
                    )
                    Spacer()
                    Button {
                        model.refreshDiagnostics()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                HealthSummary(model: model)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.diagnostics) { item in
                        DiagnosticCard(item: item)
                    }
                }

                SurfaceCard {
                    HStack(spacing: 15) {
                        SymbolTile(symbol: "wrench.and.screwdriver", color: MicroPalette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("修复工具")
                                .font(.system(size: 14, weight: .semibold))
                            Text("修复 Hooks 与基础快捷键；推理旋钮需在 Codex 中人工绑定。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("请求辅助功能权限") { model.requestAccessibility() }
                            .buttonStyle(.bordered)
                        Button("重新安装 Codex 集成") { model.installIntegration() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Text("所有服务仅监听本机回环地址，不会把输入或任务信息发送到远程服务器。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HealthSummary: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(model.systemReady ? MicroPalette.ink : Color.clear)
                    .frame(width: 54, height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(MicroPalette.ink, lineWidth: 1)
                    }
                Image(systemName: model.systemReady ? "checkmark" : "exclamationmark")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(model.systemReady ? Color.white : MicroPalette.ink)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.systemReady ? "控制链路运行正常" : "还有 \(model.blockingIssueCount) 项需要处理")
                    .font(.system(size: 17, weight: .semibold))
                Text(model.systemReady ? "TourBox 输入、Codex 集成与系统权限均已就绪。" : "下方标记项目会阻止部分或全部控制动作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.systemReady ? "READY" : "CHECK")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(model.systemReady ? Color.white : MicroPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(model.systemReady ? MicroPalette.ink : Color.clear, in: RoundedRectangle(cornerRadius: 2))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(MicroPalette.ink, lineWidth: 1)
                }
        }
        .padding(18)
        .background(MicroPalette.elevatedCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MicroPalette.glassHighlight, lineWidth: 1)
        }
    }
}

private struct DiagnosticCard: View {
    let item: SettingsModel.DiagnosticItem

    private var color: Color {
        switch item.state {
        case .ready: MicroPalette.ink
        case .actionRequired: MicroPalette.graphite
        case .inactive: Color.gray
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .ready: "正常"
        case .actionRequired: "需处理"
        case .inactive: "可选"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: item.symbol, color: color, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(stateLabel)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 2))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(color.opacity(0.65), lineWidth: 1)
                }
        }
        .padding(14)
        .frame(minHeight: 70)
        .background(MicroPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MicroPalette.line, lineWidth: 1)
        }
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.35)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(MicroPalette.ink, in: RoundedRectangle(cornerRadius: 1))
            Text(title)
                .font(.system(size: 25, weight: .black))
                .tracking(-0.35)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MappingGroupHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            SymbolTile(symbol: symbol, color: color, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(MicroPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MicroPalette.line, lineWidth: 1)
        }
    }
}

private struct SettingToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MicroPalette.accent)
                .frame(width: 32, height: 32)
                .background(MicroPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(MicroPalette.line, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 5)
    }
}

private struct InfoBanner: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MicroPalette.accent)
                .frame(width: 34, height: 34)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(MicroPalette.ink, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(13)
        .background(MicroPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MicroPalette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

private struct SymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color.opacity(0.38), lineWidth: 1)
            }
    }
}

private struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MicroPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MicroPalette.line, lineWidth: 1)
            }
    }
}

private extension TourBoxControl {
    var settingsName: String {
        switch self {
        case .knob: "旋钮按下"
        case .scroll: "滚轮按下"
        case .dial: "转盘按下"
        case .tall: "长键"
        case .short: "短键"
        case .top: "横键"
        case .side: "侧键"
        case .up: "方向键 · 上"
        case .down: "方向键 · 下"
        case .left: "方向键 · 左"
        case .right: "方向键 · 右"
        case .tour: "Tour"
        case .c1: "C1"
        case .c2: "C2"
        }
    }

    var settingsHint: String {
        switch self {
        case .knob, .scroll, .dial: "按下时触发"
        case .up, .down, .left, .right: "单击触发"
        case .c1, .c2: "快捷功能键"
        default: "单击触发"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .knob: "dial.medium"
        case .scroll: "computermouse.fill"
        case .dial: "circle.circle"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .c1, .c2: "command.square"
        case .top: "rectangle.tophalf.inset.filled"
        case .tall: "rectangle.portrait"
        case .side: "sidebar.left"
        default: "button.programmable"
        }
    }

    var settingsColor: Color {
        switch self {
        case .knob, .scroll, .dial: MicroPalette.ink
        case .up, .down, .left, .right: MicroPalette.graphite
        case .c1, .c2: Color.gray
        default: MicroPalette.ink.opacity(0.78)
        }
    }
}

private extension ButtonAction {
    var settingsName: String {
        switch self {
        case .none: "不执行"
        case .toggleFast: "切换 Fast 模式"
        case .togglePlan: "切换 Plan 模式"
        case .forkThread: "Fork 当前任务"
        case .approveOrSend: "批准 / 发送"
        case .rejectOrCancel: "拒绝 / 取消"
        case .openReview: "打开 Review"
        case .openModelPicker: "选择模型"
        case .quickChat: "快速聊天"
        case .findInChat: "当前聊天内查找"
        case .openCommandMenu: "打开命令菜单"
        case .searchFiles: "搜索项目文件"
        case .newIndependentChat: "新建独立聊天"
        case .copy: "复制"
        case .paste: "粘贴"
        case .screenshot: "截图"
        case .previousRecentChat: "上一个最近聊天"
        case .nextRecentChat: "下一个最近聊天"
        case .searchChats: "搜索所有聊天"
        case .jumpToLatest: "跳到最新消息"
        case .previousChat: "上一个任务"
        case .nextChat: "下一个任务"
        case .navigateBack: "后退"
        case .navigateForward: "前进"
        case .toggleSidebar: "切换侧边栏"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .none: "minus.circle"
        case .toggleFast: "bolt.fill"
        case .togglePlan: "list.bullet.clipboard"
        case .forkThread: "arrow.triangle.branch"
        case .approveOrSend: "paperplane.fill"
        case .rejectOrCancel: "xmark.circle"
        case .openReview: "doc.text.magnifyingglass"
        case .openModelPicker: "cpu"
        case .quickChat: "bubble.left.and.bubble.right"
        case .findInChat: "text.magnifyingglass"
        case .openCommandMenu: "command"
        case .searchFiles: "doc.text.magnifyingglass"
        case .newIndependentChat: "plus.bubble"
        case .copy: "doc.on.doc"
        case .paste: "clipboard"
        case .screenshot: "camera"
        case .previousRecentChat: "arrow.left.to.line"
        case .nextRecentChat: "arrow.right.to.line"
        case .searchChats: "magnifyingglass"
        case .jumpToLatest: "arrow.down.to.line"
        case .previousChat: "chevron.left"
        case .nextChat: "chevron.right"
        case .navigateBack: "arrow.backward"
        case .navigateForward: "arrow.forward"
        case .toggleSidebar: "sidebar.left"
        }
    }
}
