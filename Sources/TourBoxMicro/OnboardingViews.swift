import AppKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case codex
    case hooks
    case accessibility
    case preset
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .codex: L10n.tr("Connect Codex")
        case .hooks: L10n.tr("Install lifecycle hooks")
        case .accessibility: L10n.tr("Grant Accessibility")
        case .preset: L10n.tr("Connect the TourBox preset")
        case .complete: L10n.tr("Setup complete")
        }
    }

    var subtitle: String {
        switch self {
        case .codex: L10n.tr("Confirm that Codex and its local task index are available.")
        case .hooks: L10n.tr("Install authenticated hooks and the F13–F15 base shortcuts without replacing your existing configuration.")
        case .accessibility: L10n.tr("Allow TourBox Micro to send the keyboard and scroll actions you choose.")
        case .preset: L10n.tr("Import the Max/MSP preset in TourBox Console, then confirm the local hardware connection.")
        case .complete: L10n.tr("Your local control path is configured. You can revisit this assistant from the menu bar at any time.")
        }
    }

    var symbol: String {
        switch self {
        case .codex: "app.badge.checkmark"
        case .hooks: "point.3.connected.trianglepath.dotted"
        case .accessibility: "hand.raised.fill"
        case .preset: "dial.medium.fill"
        case .complete: "checkmark.seal.fill"
        }
    }
}

struct OnboardingRootView: View {
    @ObservedObject var model: SettingsModel
    let onComplete: () -> Void
    @State private var step: OnboardingStep = .codex

    private var isStepReady: Bool {
        switch step {
        case .codex:
            return isReady("codex") && isReady("database")
        case .hooks:
            return isReady("hooks") && isReady("keys")
        case .accessibility:
            return isReady("accessibility")
        case .preset:
            return isReady("tourbox")
        case .complete:
            return model.blockingIssueCount == 0
        }
    }

    var body: some View {
        ZStack {
            GlassEffectView(
                material: .underWindowBackground,
                blendingMode: .behindWindow,
                state: .active,
                emphasized: true
            )
            LinearGradient(
                colors: [Color.white.opacity(0.34), Color.gray.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                header
                Divider().opacity(0.35)
                content
                Divider().opacity(0.35)
                footer
            }
        }
        .preferredColorScheme(.light)
        .tint(Color(red: 0.08, green: 0.08, blue: 0.075))
        .ignoresSafeArea()
        .alert(model.noticeTitle, isPresented: $model.showingNotice) {
            Button(L10n.tr("OK")) {}
        } message: {
            Text(model.noticeMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("TourBox Micro")
                    .font(.system(size: 18, weight: .bold))
                Text("FIRST-RUN SETUP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.primary : Color.primary.opacity(0.14))
                        .frame(width: item == step ? 30 : 11, height: 7)
                        .animation(.easeOut(duration: 0.18), value: step)
                        .accessibilityLabel(L10n.format("Step %d: %@", item.rawValue + 1, item.title))
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 20)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: step.symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .frame(width: 66, height: 66)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                Text(step.title)
                    .font(.system(size: 28, weight: .bold))
                Text(step.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                statusBadge
            }
            .frame(width: 310, alignment: .leading)

            VStack(spacing: 11) {
                stepRows
                if step == .preset {
                    Text("The preset is generated from your device-adapted TourBox template and never modifies the TourBox Console database.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                if step == .complete, model.blockingIssueCount > 0 {
                    Text(L10n.format("You can finish now; %d optional or unresolved items remain in Diagnostics.", model.blockingIssueCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 34)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var stepRows: some View {
        switch step {
        case .codex:
            diagnosticRow("codex")
            diagnosticRow("database")
        case .hooks:
            diagnosticRow("hooks")
            diagnosticRow("keys")
            diagnosticRow("reasoning-keys")
        case .accessibility:
            diagnosticRow("accessibility")
            OnboardingInfoRow(
                title: L10n.tr("Privacy boundary"),
                detail: L10n.tr("Accessibility is used only for the configured local keyboard and scroll actions."),
                symbol: "lock.shield",
                ready: true
            )
        case .preset:
            diagnosticRow("ports")
            diagnosticRow("tourbox")
        case .complete:
            OnboardingInfoRow(
                title: L10n.tr("Local-only architecture"),
                detail: L10n.tr("Task state, hardware input, and diagnostics stay on this Mac."),
                symbol: "checkmark.shield",
                ready: true
            )
            OnboardingInfoRow(
                title: L10n.tr("Setup can be changed later"),
                detail: L10n.tr("Open Settings or rerun Setup Assistant from the menu bar."),
                symbol: "gearshape",
                ready: true
            )
        }
    }

    private var statusBadge: some View {
        Label(
            isStepReady ? L10n.tr("Ready") : L10n.tr("Action required"),
            systemImage: isStepReady ? "checkmark.circle.fill" : "circle.dashed"
        )
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L10n.tr("Back")) {
                move(by: -1)
            }
            .disabled(step == .codex)

            Button(L10n.tr("Refresh status")) {
                model.refreshDiagnostics()
            }

            Spacer()

            if step != .complete {
                Button(actionTitle) {
                    performStepAction()
                }
                .buttonStyle(.bordered)

                Button(isStepReady ? L10n.tr("Continue") : L10n.tr("Continue anyway")) {
                    move(by: 1)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(L10n.tr("Finish setup")) {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
    }

    private var actionTitle: String {
        switch step {
        case .codex: L10n.tr("Open Codex")
        case .hooks: L10n.tr("Install integration")
        case .accessibility: L10n.tr("Request permission")
        case .preset: L10n.tr("Open preset guide")
        case .complete: L10n.tr("Finish setup")
        }
    }

    private func performStepAction() {
        switch step {
        case .codex:
            model.openCodex()
        case .hooks:
            model.installIntegration()
        case .accessibility:
            model.requestAccessibility()
        case .preset:
            model.openPresetGuide()
        case .complete:
            onComplete()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            model.refreshDiagnostics()
        }
    }

    private func move(by offset: Int) {
        let next = min(max(step.rawValue + offset, 0), OnboardingStep.allCases.count - 1)
        if let nextStep = OnboardingStep(rawValue: next) {
            step = nextStep
            model.refreshDiagnostics()
        }
    }

    private func isReady(_ id: String) -> Bool {
        model.diagnosticItem(id: id)?.state == .ready
    }

    @ViewBuilder
    private func diagnosticRow(_ id: String) -> some View {
        if let item = model.diagnosticItem(id: id) {
            OnboardingInfoRow(
                title: item.title,
                detail: item.detail,
                symbol: item.symbol,
                ready: item.state == .ready
            )
        } else {
            OnboardingInfoRow(
                title: L10n.tr("Checking"),
                detail: L10n.tr("Refresh diagnostics to update this status."),
                symbol: "hourglass",
                ready: false
            )
        }
    }
}

private struct OnboardingInfoRow: View {
    let title: String
    let detail: String
    let symbol: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.primary : Color.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}
