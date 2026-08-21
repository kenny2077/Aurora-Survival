import Foundation

/// Incrementally exposes only user-facing `a` string values from Expert's
/// private JSON envelope.
final class ExpertEnvelopeStreamDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var raw = ""
    private var observedText = ""
    private var pendingDelta = ""
    private var emittedText = ""
    private var lastEmission = Date()

    func append(_ piece: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        raw += piece
        let extracted = Self.answerText(in: raw)
        guard extracted.hasPrefix(observedText) else { return [] }
        pendingDelta += extracted.dropFirst(observedText.count)
        observedText = extracted
        return flushReadyDeltas(force: false)
    }

    func finish() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return flushReadyDeltas(force: true)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return (emittedText + pendingDelta).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func flushReadyDeltas(force: Bool) -> [String] {
        var deltas: [String] = []
        while let boundary = pendingDelta.firstIndex(where: { $0.isWhitespace }) {
            let delta = String(pendingDelta[...boundary])
            pendingDelta.removeSubrange(...boundary)
            emittedText += delta
            deltas.append(delta)
            lastEmission = Date()
        }
        if !pendingDelta.isEmpty,
           force || Date().timeIntervalSince(lastEmission) >= 0.05 {
            emittedText += pendingDelta
            deltas.append(pendingDelta)
            pendingDelta = ""
            lastEmission = Date()
        }
        return deltas
    }

    static func answerText(in value: String) -> String {
        var answers: [String] = []
        var searchStart = value.startIndex
        while let key = value.range(of: #""a""#, range: searchStart..<value.endIndex) {
            var cursor = key.upperBound
            skipWhitespace(in: value, cursor: &cursor)
            guard cursor < value.endIndex, value[cursor] == ":" else {
                searchStart = key.upperBound
                continue
            }
            cursor = value.index(after: cursor)
            skipWhitespace(in: value, cursor: &cursor)
            guard cursor < value.endIndex, value[cursor] == "\"" else {
                searchStart = key.upperBound
                continue
            }
            cursor = value.index(after: cursor)
            answers.append(decodePartialJSONString(in: value, cursor: &cursor))
            searchStart = cursor
            if cursor == value.endIndex { break }
        }
        return answers.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func skipWhitespace(
        in value: String,
        cursor: inout String.Index
    ) {
        while cursor < value.endIndex, value[cursor].isWhitespace {
            cursor = value.index(after: cursor)
        }
    }

    private static func decodePartialJSONString(
        in value: String,
        cursor: inout String.Index
    ) -> String {
        var output = ""
        while cursor < value.endIndex {
            let character = value[cursor]
            cursor = value.index(after: cursor)
            if character == "\"" { break }
            guard character == "\\" else {
                output.append(character)
                continue
            }
            guard cursor < value.endIndex else { break }
            let escaped = value[cursor]
            cursor = value.index(after: cursor)
            switch escaped {
            case "\"", "\\", "/": output.append(escaped)
            case "b": output.append("\u{8}")
            case "f": output.append("\u{c}")
            case "n": output.append("\n")
            case "r": output.append("\r")
            case "t": output.append("\t")
            case "u":
                var hex = ""
                for _ in 0..<4 where cursor < value.endIndex {
                    hex.append(value[cursor])
                    cursor = value.index(after: cursor)
                }
                if hex.count == 4,
                   let scalarValue = UInt32(hex, radix: 16),
                   let scalar = UnicodeScalar(scalarValue) {
                    output.unicodeScalars.append(scalar)
                }
            default: output.append(escaped)
            }
        }
        return output
    }
}
