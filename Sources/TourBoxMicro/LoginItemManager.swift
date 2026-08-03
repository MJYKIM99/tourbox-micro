import Foundation
import ServiceManagement

enum LoginItemManager {
    private static let fallbackLabel = "com.yi.tourboxmicro.login"

    private static var fallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(fallbackLabel).plist")
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        if status == .notFound {
            return FileManager.default.fileExists(atPath: fallbackURL.path)
        }
        return status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if status == .notFound {
            try setFallbackEnabled(enabled)
            return
        }

        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            guard status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static var statusDescription: String {
        switch status {
        case .enabled:
            "已启用"
        case .requiresApproval:
            "等待在系统设置中批准"
        case .notRegistered:
            "未启用"
        case .notFound:
            isEnabled ? "已启用（本机兼容模式，下次登录生效）" : "未启用（本机兼容模式）"
        @unknown default:
            "未知"
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
