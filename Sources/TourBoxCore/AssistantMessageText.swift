import Foundation

/// Reduces an assistant message to the short, single-line summary the HUD
/// shows. Used for both rollout-derived text and lifecycle-hook text so the two
/// sources cannot disagree about how a message should look.
public enum AssistantMessageText {
    public static let maximumLength = 180

    public static func concise(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }

        var text = value
        text = text.replacingOccurrences(
            of: #"<codex_delegation>[\s\S]*?</codex_delegation>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[`*_>#]"#, with: "", options: .regularExpression)

        let lines = text.components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*(?:[-+•]|\d+[.)])\s*"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard var candidate = lines.last else { return nil }

        let endings = CharacterSet(charactersIn: "。！？!?")
        let sentences = candidate.components(separatedBy: endings)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let last = sentences.last { candidate = last }
        candidate = candidate.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !candidate.isEmpty else { return nil }
        if candidate.count > maximumLength {
            return String(candidate.prefix(maximumLength - 1))
                .trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return candidate
    }
}
