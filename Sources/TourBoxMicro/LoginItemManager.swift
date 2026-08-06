import Foundation
import ServiceManagement

enum LoginItemManager {
    struct Snapshot: Equatable {
        let isEnabled: Bool
        let statusDescription: String
    }

    private static let fallbackLabel = "com.yi.tourboxmicro.login"

    private static var fallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(fallbackLabel).plist")
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        let currentStatus = service.status
        if currentStatus == .notFound {
            try setFallbackEnabled(enabled)
            return
        }

        if enabled {
            guard currentStatus != .enabled else { return }
            try service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            guard currentStatus != .notRegistered else { return }
            try service.unregister()
        }
    }

    static func snapshot() -> Snapshot {
        let currentStatus = SMAppService.mainApp.status
        switch currentStatus {
        case .enabled:
            return Snapshot(isEnabled: true, statusDescription: "已启用")
        case .requiresApproval:
            return Snapshot(isEnabled: false, statusDescription: "等待在系统设置中批准")
        case .notRegistered:
            return Snapshot(isEnabled: false, statusDescription: "未启用")
        case .notFound:
            let fallbackEnabled = FileManager.default.fileExists(atPath: fallbackURL.path)
            return Snapshot(
                isEnabled: fallbackEnabled,
                statusDescription: fallbackEnabled
                    ? "已启用（本机兼容模式，下次登录生效）"
                    : "未启用（本机兼容模式）"
            )
        @unknown default:
            return Snapshot(isEnabled: false, statusDescription: "未知")
        }
    }

    private static func setFallbackEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default
        if enabled {
            try fileManager.createDirectory(
                at: fallbackURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let propertyList: [String: Any] = [
                "Label": fallbackLabel,
                "ProgramArguments": ["/usr/bin/open", "-b", "com.yi.tourboxmicro"],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: propertyList,
                format: .xml,
                options: 0
            )
            try data.write(to: fallbackURL, options: .atomic)
        } else if fileManager.fileExists(atPath: fallbackURL.path) {
            try fileManager.removeItem(at: fallbackURL)
        }
    }
}
