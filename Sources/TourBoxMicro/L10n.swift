import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: tr(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
