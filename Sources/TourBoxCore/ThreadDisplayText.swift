import Foundation

public enum ThreadDisplayText {
    public static func title(rawTitle: String, preview: String) -> String {
        for source in [rawTitle, preview] {
            if let delegatedInput = taggedInput(in: source) {
                let concise = conciseDelegatedTitle(delegatedInput)
                if !concise.isEmpty { return concise }
            }
        }

        let cleanedTitle = normalized(rawTitle)
        if !cleanedTitle.isEmpty { return cleanedTitle }
        let cleanedPreview = normalized(preview)
        return cleanedPreview.isEmpty ? CoreL10n.tr("Untitled task") : cleanedPreview
    }

    private static func taggedInput(in text: String) -> String? {
        guard text.localizedCaseInsensitiveContains("<codex_delegation"),
              let open = text.range(of: "<input>", options: .caseInsensitive),
              let close = text.range(
                of: "</input>",
                options: .caseInsensitive,
                range: open.upperBound..<text.endIndex
              ) else {
            return nil
        }
        return String(text[open.upperBound..<close.lowerBound])
    }

    private static func conciseDelegatedTitle(_ text: String) -> String {
        let firstParagraph = text.components(separatedBy: "\n\n").first ?? text
        let value = normalized(firstParagraph)
        guard value.count > 24 else { return value }

        let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?"]
        for (offset, character) in value.enumerated()
            where offset >= 24 && offset < 140 && terminators.contains(character) {
            return String(value.prefix(offset + 1))
        }
        guard value.count > 110 else { return value }
        return String(value.prefix(108)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
