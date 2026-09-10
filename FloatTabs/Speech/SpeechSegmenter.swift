import Foundation

enum SpeechSegmenter {
    static let defaultMaximumSegmentLength = 220
    private static let protectedAbbreviations = [
        "e.g.",
        "i.e.",
        "mr.",
        "mrs.",
        "dr.",
        "vs."
    ]

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
        let characters = Array(paragraph)

        for (index, character) in characters.enumerated() {
            current.append(character)
            guard terminators.contains(character) else { continue }
            if character == "." && (
                isDecimalPeriod(in: characters, at: index) ||
                isAbbreviationPeriod(in: characters, through: index)
            ) {
                continue
            }
            let piece = stripLeadingDecorativeMarkers(
                from: current.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if !piece.isEmpty {
                pieces.append(piece)
            }
            current.removeAll(keepingCapacity: true)
        }
        let remainder = stripLeadingDecorativeMarkers(
            from: current.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !remainder.isEmpty { pieces.append(remainder) }
        return pieces.filter { !$0.isEmpty }
    }

    private static func stripLeadingDecorativeMarkers(from text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*(?:(?:[-–—•·.…]){2,}|={2,}|>{2,}|<{2,}|/{2,}|\${2,}|#{2,})\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func isDecimalPeriod(
        in characters: [Character],
        at index: Int
    ) -> Bool {
        guard index > 0, index + 1 < characters.count else { return false }
        return characters[index - 1].isNumber && characters[index + 1].isNumber
    }

    private static func isAbbreviationPeriod(
        in characters: [Character],
        through index: Int
    ) -> Bool {
        let token = String(characters[...index])
            .split(whereSeparator: { $0.isWhitespace })
            .last
            .map(String.init)
            .map { $0.lowercased() }
        guard let token else { return false }

        return protectedAbbreviations.contains { abbreviation in
            let abbreviationCharacters = Array(abbreviation)
            return abbreviationCharacters.indices.contains { abbreviationIndex in
                abbreviationCharacters[abbreviationIndex] == "." &&
                    token == String(abbreviationCharacters[...abbreviationIndex])
            }
        }
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
