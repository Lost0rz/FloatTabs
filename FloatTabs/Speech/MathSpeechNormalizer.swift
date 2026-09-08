import Foundation

enum MathSpeechComplexity: Equatable, Sendable {
    case simple
    case moderate
    case complex
}

struct MathSpeechNormalization: Equatable, Sendable {
    let text: String
    let complexity: MathSpeechComplexity
}

/// A bounded, local math-to-speech normalizer. It intentionally supports the
/// small deterministic vocabulary used by common geometry/algebra answers and
/// turns unsupported structures into a safe semantic fallback.
enum MathSpeechNormalizer {
    static let maximumSourceLength = 1600

    private static let allowedCommands: Set<String> = [
        "cdot", "div", "frac", "ge", "le", "neq", "pm", "sqrt", "times",
    ]

    static func normalize(
        _ source: String,
        languageRole: SpeechLanguageRole = .chinese
    ) -> MathSpeechNormalization {
        let role = languageRole == .english ? SpeechLanguageRole.english : .chinese
        let fallback = role == .english
            ? "There is a complex formula here."
            : "此处有一个复杂公式。"
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.count <= maximumSourceLength else {
            return MathSpeechNormalization(text: fallback, complexity: .complex)
        }

        let unwrapped = unwrapDelimiters(trimmed)
        guard !unwrapped.isEmpty,
              balancedDelimiters(in: unwrapped),
              !containsUnsupportedStructure(unwrapped),
              !containsUnknownCommand(unwrapped) else {
            return MathSpeechNormalization(text: fallback, complexity: .complex)
        }

        let complexity = classify(unwrapped)
        guard complexity != .complex else {
            return MathSpeechNormalization(text: fallback, complexity: .complex)
        }

        let normalized = role == .english
            ? renderEnglish(unwrapped)
            : renderChinese(unwrapped)
        guard let normalized,
              !normalized.isEmpty,
              SpeechSpeakabilityFilter.containsSpeakableContent(normalized) else {
            return MathSpeechNormalization(text: fallback, complexity: .complex)
        }
        return MathSpeechNormalization(text: normalized, complexity: complexity)
    }

    private static func unwrapDelimiters(_ source: String) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers = [("\\(", "\\)"), ("\\[", "\\]"), ("$$", "$$"), ("$", "$")]
        for (prefix, suffix) in wrappers where value.hasPrefix(prefix) && value.hasSuffix(suffix) {
            value.removeFirst(prefix.count)
            value.removeLast(suffix.count)
            break
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func balancedDelimiters(in source: String) -> Bool {
        var braces = 0
        var parentheses = 0
        var brackets = 0
        for character in source {
            switch character {
            case "{": braces += 1
            case "}":
                braces -= 1
                if braces < 0 { return false }
            case "(": parentheses += 1
            case ")":
                parentheses -= 1
                if parentheses < 0 { return false }
            case "[": brackets += 1
            case "]":
                brackets -= 1
                if brackets < 0 { return false }
            default: break
            }
        }
        return braces == 0 && parentheses == 0 && brackets == 0
    }

    private static func containsUnsupportedStructure(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        let complexMarkers = [
            "\\begin", "\\end", "matrix", "pmatrix", "bmatrix", "cases", "aligned", "array",
            "\\sum", "\\prod", "\\int", "\\lim", "\\operatorname", "\\left", "\\right",
            "\\overline", "\\underline", "\\text{",
        ]
        if complexMarkers.contains(where: lowercased.contains) { return true }
        return source.filter { $0 == "{" }.count > 4
            || source.filter { $0 == "^" }.count > 4
            || source.filter { $0 == "\\" }.count > 8
    }

    private static func containsUnknownCommand(_ source: String) -> Bool {
        var index = source.startIndex
        while index < source.endIndex {
            guard source[index] == "\\" else {
                index = source.index(after: index)
                continue
            }
            let commandStart = source.index(after: index)
            var commandEnd = commandStart
            while commandEnd < source.endIndex, source[commandEnd].isLetter {
                commandEnd = source.index(after: commandEnd)
            }
            if commandEnd == commandStart {
                index = commandEnd
                continue
            }
            let command = String(source[commandStart..<commandEnd]).lowercased()
            if !allowedCommands.contains(command) { return true }
            index = commandEnd
        }
        return false
    }

    private static func classify(_ source: String) -> MathSpeechComplexity {
        let fractionCount = source.components(separatedBy: "\\frac").count - 1
        let sqrtCount = source.components(separatedBy: "\\sqrt").count - 1
        let nesting = maximumBraceDepth(in: source)
        if fractionCount > 1 || sqrtCount > 1 || nesting > 2 { return .complex }
        if fractionCount == 1 || sqrtCount == 1 || source.contains("(") || source.contains("[") {
            return .moderate
        }
        return .simple
    }

    private static func maximumBraceDepth(in source: String) -> Int {
        var depth = 0
        var maximum = 0
        for character in source {
            if character == "{" {
                depth += 1
                maximum = max(maximum, depth)
            } else if character == "}" {
                depth = max(0, depth - 1)
            }
        }
        return maximum
    }

    private static func renderChinese(_ source: String) -> String? {
        guard let expression = expandStructuredTokens(source) else { return nil }
        if let division = expression.range(of: " / "),
           expression[..<division.lowerBound].contains("("),
           expression[division.upperBound...].first?.isNumber == true {
            let numerator = String(expression[..<division.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "（）"))
            let denominator = String(expression[division.upperBound...])
            guard let renderedNumerator = renderChineseAtoms(numerator) else { return nil }
            return "\(renderedNumerator)，整体除以 \(denominator)"
        }
        return renderChineseAtoms(expression)
    }

    private static func renderEnglish(_ source: String) -> String? {
        guard let expression = expandStructuredTokens(source) else { return nil }
        if let division = expression.range(of: " / "),
           expression[..<division.lowerBound].contains("("),
           expression[division.upperBound...].first?.isNumber == true {
            let numerator = String(expression[..<division.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            let denominator = String(expression[division.upperBound...])
            guard let renderedNumerator = renderEnglishAtoms(numerator) else { return nil }
            return "\(renderedNumerator) divided by \(denominator)"
        }
        return renderEnglishAtoms(expression)
    }

    private static func expandStructuredTokens(_ source: String) -> String? {
        var value = source
        value = value.replacingOccurrences(of: ">=", with: " ≥ ")
        value = value.replacingOccurrences(of: "<=", with: " ≤ ")
        value = value.replacingOccurrences(of: "!=", with: " ≠ ")
        value = value.replacingOccurrences(of: "sqrt(", with: "√(")
        value = value.replacingOccurrences(of: "\\times", with: " × ")
        value = value.replacingOccurrences(of: "\\cdot", with: " × ")
        value = value.replacingOccurrences(of: "\\div", with: " ÷ ")
        value = value.replacingOccurrences(of: "\\ge", with: " ≥ ")
        value = value.replacingOccurrences(of: "\\le", with: " ≤ ")
        value = value.replacingOccurrences(of: "\\neq", with: " ≠ ")
        value = value.replacingOccurrences(of: "\\pm", with: " ± ")
        value = replaceSimpleFractions(in: value)
        value = replaceSimpleSquareRoots(in: value)
        value = value.replacingOccurrences(of: "\\{", with: "{")
        value = value.replacingOccurrences(of: "\\}", with: "}")
        value = value.replacingOccurrences(of: "\\,", with: " ")
        value = value.replacingOccurrences(of: "\\ ", with: " ")
        value = replaceUnicodeSuperscripts(in: value)
        value = replaceCaretSuperscripts(in: value)
        guard !value.contains("\\") else { return nil }
        return value
            .replacingOccurrences(of: "−", with: " - ")
            .replacingOccurrences(of: "–", with: " - ")
            .replacingOccurrences(of: "—", with: " - ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func replaceSimpleFractions(in source: String) -> String {
        var value = source
        let pattern = #"\\frac\{([^{}]+)\}\{([^{}]+)\}"#
        while let match = value.range(of: pattern, options: .regularExpression) {
            let matched = String(value[match])
            let pieces = matched.dropFirst(6).dropLast()
            let parts = pieces.split(separator: "}", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { break }
            let numerator = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "{"))
            let denominator = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "{"))
            value.replaceSubrange(match, with: "(\(numerator)) / \(denominator)")
        }
        return value
    }

    private static func replaceSimpleSquareRoots(in source: String) -> String {
        var value = source
        let pattern = #"\\sqrt\{([^{}]+)\}"#
        while let match = value.range(of: pattern, options: .regularExpression) {
            let matched = String(value[match])
            guard let open = matched.firstIndex(of: "{"), let close = matched.lastIndex(of: "}") else { break }
            let content = matched[matched.index(after: open)..<close]
            value.replaceSubrange(match, with: "√(\(content))")
        }
        return value
    }

    private static func replaceUnicodeSuperscripts(in source: String) -> String {
        source
            .replacingOccurrences(of: "²", with: "^2")
            .replacingOccurrences(of: "³", with: "^3")
    }

    private static func replaceCaretSuperscripts(in source: String) -> String {
        var value = source
        let braced = #"([A-Za-z0-9)])\^\{([A-Za-z0-9]+)\}"#
        value = value.replacingOccurrences(of: braced, with: "$1^$2", options: .regularExpression)
        return value
    }

    private static func renderChineseAtoms(_ source: String) -> String? {
        var output: [String] = []
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace {
                index = source.index(after: index)
                continue
            }
            if character.isNumber {
                var end = index
                while end < source.endIndex,
                      source[end].isNumber || source[end] == "." {
                    end = source.index(after: end)
                }
                output.append(String(source[index..<end]))
                index = end
                continue
            }
            if character == "^" {
                let exponentStart = source.index(after: index)
                guard exponentStart < source.endIndex else { return nil }
                var exponentEnd = exponentStart
                while exponentEnd < source.endIndex, source[exponentEnd].isNumber || source[exponentEnd].isLetter {
                    exponentEnd = source.index(after: exponentEnd)
                }
                let exponent = String(source[exponentStart..<exponentEnd])
                guard let prior = output.popLast() else { return nil }
                if exponent == "2" { output.append("\(prior) 的平方") }
                else if exponent == "3" { output.append("\(prior) 的立方") }
                else { output.append("\(prior) 的 \(exponent) 次方") }
                index = exponentEnd
                continue
            }
            if character == "√" {
                let start = source.index(after: index)
                let (content, next) = consumeGroup(in: source, from: start)
                guard let content else { return nil }
                output.append("根号 \(renderChineseAtoms(content) ?? content)")
                index = next
                continue
            }
            if character == "|" {
                let start = source.index(after: index)
                guard let end = source[start...].firstIndex(of: "|") else { return nil }
                let content = String(source[start..<end])
                output.append("\(renderChineseAtoms(content) ?? content) 的绝对值")
                index = source.index(after: end)
                continue
            }
            let atom = String(character)
            switch character {
            case "*", "+": output.append("加")
            case "-": output.append("减")
            case "×": output.append("乘")
            case "÷", "/": output.append("除以")
            case "=": output.append("等于")
            case "≠": output.append("不等于")
            case ">": output.append("大于")
            case "<": output.append("小于")
            case "≥": output.append("大于等于")
            case "≤": output.append("小于等于")
            case ":": output.append("比")
            case "±": output.append("加减")
            case "%": output.append("百分之")
            case "(", ")", "[", "]": break
            default:
                if character.isLetter || character.isNumber || character == "." {
                    output.append(atom)
                } else if !character.isPunctuation && !character.isSymbol {
                    output.append(atom)
                }
            }
            index = source.index(after: index)
        }
        return joinChinese(output)
    }

    private static func renderEnglishAtoms(_ source: String) -> String? {
        var output: [String] = []
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace {
                index = source.index(after: index)
                continue
            }
            if character.isNumber {
                var end = index
                while end < source.endIndex,
                      source[end].isNumber || source[end] == "." {
                    end = source.index(after: end)
                }
                output.append(String(source[index..<end]))
                index = end
                continue
            }
            if character == "^" {
                let exponentStart = source.index(after: index)
                guard exponentStart < source.endIndex else { return nil }
                var exponentEnd = exponentStart
                while exponentEnd < source.endIndex, source[exponentEnd].isNumber || source[exponentEnd].isLetter {
                    exponentEnd = source.index(after: exponentEnd)
                }
                let exponent = String(source[exponentStart..<exponentEnd])
                guard let prior = output.popLast() else { return nil }
                if exponent == "2" { output.append("\(prior) squared") }
                else if exponent == "3" { output.append("\(prior) cubed") }
                else { output.append("\(prior) to the power of \(exponent)") }
                index = exponentEnd
                continue
            }
            if character == "√" {
                let start = source.index(after: index)
                let (content, next) = consumeGroup(in: source, from: start)
                guard let content else { return nil }
                output.append("square root of \(renderEnglishAtoms(content) ?? content)")
                index = next
                continue
            }
            if character == "|" {
                let start = source.index(after: index)
                guard let end = source[start...].firstIndex(of: "|") else { return nil }
                let content = String(source[start..<end])
                output.append("\(renderEnglishAtoms(content) ?? content) absolute value")
                index = source.index(after: end)
                continue
            }
            let atom = String(character)
            switch character {
            case "*", "+": output.append("plus")
            case "-", "−": output.append("minus")
            case "×": output.append("times")
            case "÷", "/": output.append("divided by")
            case "=": output.append("equals")
            case "≠": output.append("not equal to")
            case ">": output.append("greater than")
            case "<": output.append("less than")
            case "≥": output.append("greater than or equal to")
            case "≤": output.append("less than or equal to")
            case ":": output.append("to")
            case "±": output.append("plus or minus")
            case "%": output.append("percent")
            case "(", ")", "[", "]": break
            default:
                if character.isLetter || character.isNumber || character == "." {
                    output.append(atom)
                } else if !character.isPunctuation && !character.isSymbol {
                    output.append(atom)
                }
            }
            index = source.index(after: index)
        }
        return output.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func consumeGroup(
        in source: String,
        from start: String.Index
    ) -> (String?, String.Index) {
        guard start < source.endIndex else { return (nil, start) }
        guard source[start] == "(" || source[start] == "[" || source[start] == "{" else {
            return (String(source[start...]), source.endIndex)
        }
        let open = source[start]
        let close: Character = open == "(" ? ")" : open == "[" ? "]" : "}"
        var depth = 0
        var index = start
        while index < source.endIndex {
            if source[index] == open { depth += 1 }
            if source[index] == close {
                depth -= 1
                if depth == 0 {
                    return (
                        String(source[source.index(after: start)..<index]),
                        source.index(after: index)
                    )
                }
            }
            index = source.index(after: index)
        }
        return (nil, source.endIndex)
    }

    private static func joinChinese(_ values: [String]) -> String {
        values.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
