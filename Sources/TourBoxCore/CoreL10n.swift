import Foundation

enum CoreL10n {
    static func tr(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
