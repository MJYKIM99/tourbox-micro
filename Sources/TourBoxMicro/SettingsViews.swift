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
        case .overview: L10n.tr("Overview")
        case .controls: L10n.tr("Control mapping")
        case .diagnostics: L10n.tr("Diagnostics")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: L10n.tr("Runtime and integrations")
        case .controls: L10n.tr("Customize hardware actions")
        case .diagnostics: L10n.tr("Connection and permission status")
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
            Button(L10n.tr("OK")) {}
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
                    Text("Local only")
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
                    Text(model.tourBoxConnected ? L10n.tr("Device online") : L10n.tr("Waiting for device"))
                        .font(.caption.weight(.semibold))
                    Text(model.tourBoxConnected ? L10n.tr("TourBox connected") : model.connectionStatus)
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
                Text("Task slots")
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
        case .priority: L10n.tr("Priority order")
        case .recent: L10n.tr("Recently used order")
        case .pinned: L10n.tr("Pinned task order")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "TOURBOX × CODEX",
                    title: "Overview",
                    subtitle: "Keep your hardware controls in sync with your Codex workflow."
                )

                OverviewHero(model: model)

                HStack(spacing: 12) {
                    MetricCard(
                        title: "TourBox",
                        value: model.tourBoxConnected ? L10n.tr("Connected") : L10n.tr("Disconnected"),
                        detail: "TCP 50500",
                        symbol: "dial.medium",
                        color: MicroPalette.ink
                    )
                    MetricCard(
                        title: "Task slots",
                        value: "\(model.assignedSlotCount) / 6",
                        detail: slotModeDetail,
                        symbol: "square.stack.3d.up",
                        color: MicroPalette.graphite
                    )
                    MetricCard(
                        title: "System status",
                        value: model.systemReady
                            ? L10n.tr("All ready")
                            : L10n.format("%d items need attention", model.blockingIssueCount),
                        detail: model.systemReady ? L10n.tr("Integrations are healthy") : L10n.tr("Review Diagnostics"),
                        symbol: model.systemReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        color: model.systemReady ? MicroPalette.ink : MicroPalette.graphite
                    )
                }

                SectionLabel(title: "Runtime", subtitle: "Display and launch options")

                HStack(alignment: .top, spacing: 14) {
                    SurfaceCard {
                        VStack(spacing: 0) {
                            SettingToggleRow(
                                title: "Six-task status HUD",
                                detail: "Show task progress and alerts at the edge of the screen",
                                symbol: "rectangle.on.rectangle",
                                isOn: Binding(
                                    get: { model.hudVisible },
                                    set: { model.setHUDVisible($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            VStack(alignment: .leading, spacing: 10) {
                                Label("HUD style", systemImage: "square.grid.3x2")
                                    .font(.system(size: 13, weight: .semibold))
                                Picker("HUD style", selection: Binding(
                                    get: { model.hudStyle },
                                    set: { model.setHUDStyle($0) }
                                )) {
                                    Text("Glass lights").tag(HUDStyle.glassLights)
                                    Text("Detailed list").tag(HUDStyle.taskList)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                Text(model.hudStyle == .glassLights
                                     ? L10n.tr("Six glowing tiles stay at the lower-left and show task state with color.")
                                     : L10n.tr("Show full task titles, projects, and runtime states."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "Hover task details",
                                detail: "Show task, project, and current state when pointing at a light",
                                symbol: "cursorarrow.motionlines",
                                isOn: Binding(
                                    get: { model.hudHoverDetailsEnabled },
                                    set: { model.setHUDHoverDetails($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "Light state animations",
                                detail: "Animate state changes, hover, and alerts without continuous idle work",
                                symbol: "sparkles",
                                isOn: Binding(
                                    get: { model.hudAnimationsEnabled },
                                    set: { model.setHUDAnimations($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "State change notifications",
                                detail: "Briefly show a task card for completion, input requests, or errors",
                                symbol: "bell.badge",
                                isOn: Binding(
                                    get: { model.hudStatusNotificationsEnabled },
                                    set: { model.setHUDStatusNotifications($0) }
                                )
                            )
                            Divider().padding(.leading, 44)
                            SettingToggleRow(
                                title: "Launch at login",
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
                            Label("Task slot order", systemImage: "arrow.up.arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Choose which Codex tasks fill the six hardware slots first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Picker("Task slot order", selection: Binding(
                                get: { model.slotMode },
                                set: { model.setSlotMode($0) }
                            )) {
                                Text("Priority").tag(SlotMode.priority)
                                Text("Recent").tag(SlotMode.recent)
                                Text("Pinned").tag(SlotMode.pinned)
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
                            Text("Codex integration")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Install hooks and base shortcuts automatically; bind the reasoning knob once in Codex.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reinstall integration") { model.installIntegration() }
                            .buttonStyle(.bordered)
                        Button("Open Codex") { model.openCodex() }
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
                        Text(model.tourBoxConnected ? L10n.tr("ONLINE") : L10n.tr("STANDBY"))
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.white.opacity(0.7))

                Spacer()

                Text("Turn TourBox into a\nphysical Codex console")
                    .font(.system(size: 24, weight: .black))
                    .tracking(-0.45)
                Text("ROTATE / SWITCH / APPROVE / NAVIGATE")
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
                        title: "Control mapping",
                        subtitle: "Choose the Codex or general action triggered by each physical control."
                    )
                    Spacer()
                    Button("Restore defaults") { model.resetMapping() }
                        .buttonStyle(.bordered)
                }

                InfoBanner(
                    symbol: "lock.shield",
                    title: "Safety actions stay fixed",
                    detail: "Hold Short for push-to-talk; Tour + C1/C2/directions selects six tasks; Tour + knob/scroll/dial/top opens Quick Chat, Find, Commands, and File Search."
                )

                MappingGroupHeader(title: "Rotary controls", subtitle: "Press actions are customizable; rotation provides continuous navigation")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach([TourBoxControl.knob, .scroll, .dial], id: \.self) { control in
                        MappingTile(model: model, control: control)
                    }
                }

                MappingGroupHeader(title: "Control area", subtitle: "Frequent operations and confirmation actions")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach([TourBoxControl.top, .tall, .side, .c1, .c2], id: \.self) { control in
                        MappingTile(model: model, control: control)
                    }
                }

                MappingGroupHeader(title: "Directional pad", subtitle: "Screenshots, recent chat switching, and review")
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
                        title: "Diagnostics",
                        subtitle: "Check the complete local path from TourBox input to Codex actions."
                    )
                    Spacer()
                    Button {
                        model.refreshDiagnostics()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
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
                            Text("Repair tools")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Repair hooks and base shortcuts; bind the reasoning knob manually in Codex.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Request Accessibility") { model.requestAccessibility() }
                            .buttonStyle(.bordered)
                        Button("Reinstall Codex integration") { model.installIntegration() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Text("All services listen only on loopback and never send input or task information to a remote server.")
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
                Text(model.systemReady
                    ? L10n.tr("The control path is healthy")
                    : L10n.format("%d items need attention", model.blockingIssueCount))
                    .font(.system(size: 17, weight: .semibold))
                Text(model.systemReady
                    ? L10n.tr("TourBox input, Codex integration, and system permissions are ready.")
                    : L10n.tr("Items marked below may block some or all control actions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.systemReady ? L10n.tr("READY") : L10n.tr("CHECK"))
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
        case .ready: L10n.tr("Ready")
        case .actionRequired: L10n.tr("Action required")
        case .inactive: L10n.tr("Optional")
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
            Text(L10n.tr(eyebrow))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.35)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(MicroPalette.ink, in: RoundedRectangle(cornerRadius: 1))
            Text(L10n.tr(title))
                .font(.system(size: 25, weight: .black))
                .tracking(-0.35)
            Text(L10n.tr(subtitle))
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
            Text(L10n.tr(title))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.tr(subtitle))
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
            Text(L10n.tr(title))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.tr(subtitle))
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
                Text(L10n.tr(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.tr(value))
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.tr(detail))
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
                Text(L10n.tr(title))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.tr(detail))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(L10n.tr(title), isOn: $isOn)
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
                Text(L10n.tr(title)).font(.system(size: 13, weight: .semibold))
                Text(L10n.tr(detail)).font(.caption).foregroundStyle(.secondary)
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
        case .knob: L10n.tr("Knob press")
        case .scroll: L10n.tr("Scroll press")
        case .dial: L10n.tr("Dial press")
        case .tall: L10n.tr("Tall button")
        case .short: L10n.tr("Short button")
        case .top: L10n.tr("Top button")
        case .side: L10n.tr("Side button")
        case .up: L10n.tr("Direction · Up")
        case .down: L10n.tr("Direction · Down")
        case .left: L10n.tr("Direction · Left")
        case .right: L10n.tr("Direction · Right")
        case .tour: "Tour"
        case .c1: "C1"
        case .c2: "C2"
        }
    }

    var settingsHint: String {
        switch self {
        case .knob, .scroll, .dial: L10n.tr("Triggered on press")
        case .up, .down, .left, .right: L10n.tr("Triggered on click")
        case .c1, .c2: L10n.tr("Shortcut button")
        default: L10n.tr("Triggered on click")
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
        case .none: L10n.tr("Do nothing")
        case .toggleFast: L10n.tr("Toggle Fast mode")
        case .togglePlan: L10n.tr("Toggle Plan mode")
        case .forkThread: L10n.tr("Fork current task")
        case .approveOrSend: L10n.tr("Approve / Send")
        case .rejectOrCancel: L10n.tr("Reject / Cancel")
        case .openReview: L10n.tr("Open Review")
        case .openModelPicker: L10n.tr("Choose model")
        case .quickChat: L10n.tr("Quick Chat")
        case .findInChat: L10n.tr("Find in current chat")
        case .openCommandMenu: L10n.tr("Open command menu")
        case .searchFiles: L10n.tr("Search project files")
        case .newIndependentChat: L10n.tr("New independent chat")
        case .copy: L10n.tr("Copy")
        case .paste: L10n.tr("Paste")
        case .screenshot: L10n.tr("Screenshot")
        case .previousRecentChat: L10n.tr("Previous recent chat")
        case .nextRecentChat: L10n.tr("Next recent chat")
        case .searchChats: L10n.tr("Search all chats")
        case .jumpToLatest: L10n.tr("Jump to latest message")
        case .previousChat: L10n.tr("Previous task")
        case .nextChat: L10n.tr("Next task")
        case .navigateBack: L10n.tr("Back")
        case .navigateForward: L10n.tr("Forward")
        case .toggleSidebar: L10n.tr("Toggle sidebar")
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
