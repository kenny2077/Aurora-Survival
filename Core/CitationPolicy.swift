import Foundation

public struct CitationPolicy: Sendable {
    public init() {}

    public func validatedText(_ text: String, evidenceCount: Int) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard evidenceCount > 0 else { return text }

        let pattern = #"\[(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        for match in matches {
            guard match.numberOfRanges == 2,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let number = Int(text[numberRange]),
                  (1...evidenceCount).contains(number)
            else { return nil }
        }
        return text
    }
}
