import Foundation

enum ModelLabelFormatter {
    private static let maximumDisplayLength = 18
    private static let supportedGPTSuffixes: Set<String> = ["mini", "nano", "pro", "max"]

    static func displayName(for rawLabel: String) -> String {
        let tokens = normalizedTokens(from: rawLabel)
        guard let head = tokens.first?.lowercased(), !head.isEmpty else {
            return "Model unavailable"
        }

        let candidate: String
        switch head {
        case "gpt":
            candidate = formattedOpenAIName(
                prefix: "GPT",
                tokens: tokens,
                separator: "-",
                allowedSuffixes: supportedGPTSuffixes
            )
        case "glm":
            candidate = formattedOpenAIName(prefix: "GLM", tokens: tokens, separator: "-")
        case "kimi":
            candidate = formattedProviderName(prefix: "Kimi", tokens: tokens)
        default:
            candidate = fallbackName(from: tokens)
        }

        return tailTruncate(candidate, maximumLength: maximumDisplayLength)
    }

    private static func normalizedTokens(from rawLabel: String) -> [String] {
        rawLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func formattedOpenAIName(
        prefix: String,
        tokens: [String],
        separator: String,
        allowedSuffixes: Set<String> = []
    ) -> String {
        guard tokens.count >= 2 else {
            return prefix
        }

        let main = tokens[1].uppercased() == tokens[1]
            ? tokens[1]
            : tokens[1].capitalized

        guard tokens.count == 3 else {
            return "\(prefix)\(separator)\(main)"
        }

        let suffix = tokens[2].lowercased()
        guard allowedSuffixes.contains(suffix) else {
            return "\(prefix)\(separator)\(main)"
        }

        return "\(prefix)\(separator)\(main)\(separator)\(suffix)"
    }

    private static func formattedProviderName(prefix: String, tokens: [String]) -> String {
        guard tokens.count >= 2 else {
            return prefix
        }

        let provider = prefix
        let model = tokens[1].capitalized

        if tokens.count == 2 {
            return "\(provider) \(model)"
        }

        return "\(provider) \(model)"
    }

    private static func fallbackName(from tokens: [String]) -> String {
        guard !tokens.isEmpty else {
            return "Model unavailable"
        }

        let normalized = tokens
            .prefix(3)
            .map { token in
                if token == token.uppercased() {
                    return token
                }

                return token.prefix(1).uppercased() + token.dropFirst().lowercased()
            }
            .joined(separator: " ")

        return normalized.isEmpty ? "Model unavailable" : normalized
    }

    private static func tailTruncate(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength, maximumLength > 1 else {
            return value
        }

        let boundary = value.index(value.startIndex, offsetBy: maximumLength - 1)
        return String(value[..<boundary]) + "…"
    }
}
