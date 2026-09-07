import Foundation

enum SpeechSegmenter {
    static let defaultMaximumSegmentLength = 220

    static func segment(
        _ text: String,
        maximumLength: Int = defaultMaximumSegmentLength
    ) -> [String] {
        let limit = max(1, maximumLength)
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isWhitespace && $0 != "\n" })
            .joined(separator: " ")

        guard !normalized.isEmpty else { return [] }

        let paragraphs = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        var result: [String] = []
        for paragraph in paragraphs.isEmpty ? [normalized] : paragraphs {
            for sentence in sentencePieces(paragraph) {
                result.append(contentsOf: boundedPieces(sentence, maximumLength: limit))
            }
        }
        return result
    }

    private static func sentencePieces(_ paragraph: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "；", ";"]
        var pieces: [String] = []
        var current = ""

        for character in paragraph {
            current.append(character)
            if terminators.contains(character) {
                pieces.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty { pieces.append(remainder) }
        return pieces.filter { !$0.isEmpty }
    }

    private static func boundedPieces(_ text: String, maximumLength: Int) -> [String] {
        guard text.count > maximumLength else { return [text] }

        var pieces: [String] = []
        var remainder = text[...]
        while remainder.count > maximumLength {
            let boundary = remainder.index(
                remainder.startIndex,
                offsetBy: maximumLength
            )
            let window = remainder[..<boundary]
            let splitIndex = window.lastIndex(where: { $0 == " " || $0 == "\t" })
                ?? boundary
            let candidate = remainder[..<splitIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                pieces.append(candidate)
            }
            remainder = remainder[splitIndex...]
                .trimmingCharacters(in: .whitespacesAndNewlines)[...]
        }
        let finalPiece = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalPiece.isEmpty { pieces.append(finalPiece) }
        return pieces
    }
}
