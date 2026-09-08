import Foundation

enum SpeechContentBlockKind: String, Equatable, Sendable {
    case paragraph
    case heading
    case listItem
    case quote
    case code
    case table
    case link
}

struct SpeechContentBlock: Equatable, Sendable {
    let kind: SpeechContentBlockKind
    let text: String
    let level: Int?
}

enum SpeechSpeakabilityFilter {
    /// A segment may retain punctuation for sentence boundaries, but it must
    /// contain at least one letter or digit before it reaches Apple TTS.
    static func containsSpeakableContent(_ text: String) -> Bool {
        text.contains { character in
            character.isLetter || character.isNumber
        }
    }
}

enum SpeechContentCleaner {
    static func clean(_ blocks: [SpeechContentBlock]) -> String {
        blocks.compactMap(clean)
            .joined(separator: "\n\n")
    }

    static func clean(_ block: SpeechContentBlock) -> String? {
        switch block.kind {
        case .code, .table:
            return nil
        case .paragraph, .heading, .listItem, .quote, .link:
            break
        }

        var text = block.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if isRawMachineContent(text) { return nil }

        text = replaceMarkdownLinks(in: text)
        text = text
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(
                of: #"(?<!\w)[*_](?=\S)|(?<=\S)[*_](?!\w)"#,
                with: "",
                options: .regularExpression
            )
        text = text.replacingOccurrences(
            of: #"^\s{0,3}#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
        if block.kind == .listItem {
            text = text.replacingOccurrences(
                of: #"^\s{0,3}(?:[-+*•‣◦]|\d+[.)、．])(?:\s+|$)"#,
                with: "",
                options: .regularExpression
            )
        } else if block.kind == .quote {
            text = text.replacingOccurrences(
                of: #"^\s{0,3}>\s?"#,
                with: "",
                options: .regularExpression
            )
        }
        text = replaceLongURLs(in: text)
        text = replaceLongPaths(in: text)
        text = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty,
              SpeechSpeakabilityFilter.containsSpeakableContent(text) else {
            return nil
        }
        return text
    }

    private static func isRawMachineContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return true
        }
        let lines = trimmed.split(separator: "\n")
        let stackTraceLines = lines.filter {
            $0.range(of: #"^\s*(?:at\s+|Traceback|[A-Za-z0-9_.]+Exception:)"#, options: .regularExpression) != nil
        }
        let diffLines = lines.filter {
            $0.hasPrefix("diff --git")
                || $0.hasPrefix("--- ")
                || $0.hasPrefix("+++ ")
                || $0.hasPrefix("@@")
        }
        return lines.count >= 3 && (
            stackTraceLines.count * 2 >= lines.count
                || diffLines.count * 2 >= lines.count
        )
    }

    private static func replaceMarkdownLinks(in text: String) -> String {
        text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private static func replaceLongURLs(in text: String) -> String {
        text.replacingOccurrences(
            of: #"https?://[^\s]+"#,
            with: "链接",
            options: .regularExpression
        )
    }

    private static func replaceLongPaths(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<!\S)(?:/Users/|/private/|/var/|/tmp/)[^\s]+"#,
            with: "路径",
            options: .regularExpression
        )
    }
}
