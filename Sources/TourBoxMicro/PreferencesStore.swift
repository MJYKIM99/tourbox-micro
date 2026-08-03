import Foundation
import TourBoxCore

enum HUDStyle: String, Codable, CaseIterable, Hashable {
    case glassLights
    case taskList
}

enum PreferencesStore {
    private static let mappingKey = "inputMapping.v1"
    private static let slotModeKey = "slotMode.v1"
    private static let hudVisibleKey = "hudVisible.v1"
    private static let hudStyleKey = "hudStyle.v1"
    private static let hudHoverDetailsKey = "hudHoverDetails.v1"
    private static let hudStatusNotificationsKey = "hudStatusNotifications.v1"
    private static let hudAnimationsKey = "hudAnimations.v1"

    static func loadMapping() -> InputMappingConfiguration {
        guard let data = UserDefaults.standard.data(forKey: mappingKey),
              let mapping = try? JSONDecoder().decode(InputMappingConfiguration.self, from: data) else {
            return .default
        }
        return mapping
    }

    static func saveMapping(_ mapping: InputMappingConfiguration) {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        UserDefaults.standard.set(data, forKey: mappingKey)
    }

    static func loadSlotMode() -> SlotMode {
        guard let rawValue = UserDefaults.standard.string(forKey: slotModeKey),
              let mode = SlotMode(rawValue: rawValue) else {
            return .priority
        }
        return mode
    }

    static func saveSlotMode(_ mode: SlotMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: slotModeKey)
    }

    static func loadHUDVisible() -> Bool {
        guard UserDefaults.standard.object(forKey: hudVisibleKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hudVisibleKey)
    }

    static func saveHUDVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: hudVisibleKey)
    }

    static func loadHUDStyle() -> HUDStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: hudStyleKey),
              let style = HUDStyle(rawValue: rawValue) else {
            return .glassLights
        }
        return style
    }

    static func saveHUDStyle(_ style: HUDStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: hudStyleKey)
    }

    static func loadHUDHoverDetails() -> Bool {
        guard UserDefaults.standard.object(forKey: hudHoverDetailsKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hudHoverDetailsKey)
    }

    static func saveHUDHoverDetails(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: hudHoverDetailsKey)
    }

    static func loadHUDStatusNotifications() -> Bool {
        guard UserDefaults.standard.object(forKey: hudStatusNotificationsKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hudStatusNotificationsKey)
    }

    static func saveHUDStatusNotifications(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: hudStatusNotificationsKey)
    }

    static func loadHUDAnimations() -> Bool {
        guard UserDefaults.standard.object(forKey: hudAnimationsKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hudAnimationsKey)
    }

    static func saveHUDAnimations(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: hudAnimationsKey)
    }
}
