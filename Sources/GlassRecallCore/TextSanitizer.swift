import Foundation

public struct SanitizedTextResult: Sendable, Equatable {
    public let cleanText: String
    public let redactedCount: Int
    public let extractedURLs: [String]
    public let detectedTags: [String]

    public init(
        cleanText: String,
        redactedCount: Int,
        extractedURLs: [String],
        detectedTags: [String]
    ) {
        self.cleanText = cleanText
        self.redactedCount = redactedCount
        self.extractedURLs = extractedURLs
        self.detectedTags = detectedTags
    }
}

public enum TextSanitizer {
    private struct RedactionRule: Sendable {
        let label: String
        let pattern: String
    }

    private static let rules: [RedactionRule] = [
        RedactionRule(label: "PRIVATE_KEY", pattern: #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#),
        RedactionRule(label: "ANTHROPIC_KEY", pattern: #"\bsk-ant-[A-Za-z0-9_-]{16,}\b"#),
        RedactionRule(label: "OPENAI_KEY", pattern: #"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"#),
        RedactionRule(label: "GITHUB_TOKEN", pattern: #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b"#),
        RedactionRule(label: "GITHUB_PAT", pattern: #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#),
        RedactionRule(label: "AWS_KEY", pattern: #"\bAKIA[0-9A-Z]{16}\b"#),
        RedactionRule(label: "STRIPE_KEY", pattern: #"\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#),
        RedactionRule(label: "SLACK_TOKEN", pattern: #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#),
        RedactionRule(label: "GOOGLE_API_KEY", pattern: #"\bAIza[0-9A-Za-z_-]{35}\b"#),
        RedactionRule(label: "JWT", pattern: #"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#),
        RedactionRule(label: "BEARER_TOKEN", pattern: #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}"#),
        RedactionRule(label: "SECRET_ASSIGNMENT", pattern: #"(?i)\b(password|passwd|api[_-]?key|client[_-]?secret|access[_-]?token|secret[_-]?key)\s*[:=]\s*["']?[^\s"']{6,}["']?"#)
    ]

    public static func sanitize(_ rawText: String, redactSecrets: Bool = true) -> SanitizedTextResult {
        // Normalize lines and drop exact duplicate adjacent OCR lines
        var normalizedLines: [String] = []
        var seenRecent = Set<String>()
        for line in rawText.components(separatedBy: .newlines) {
            let trimmed = line
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !seenRecent.contains(trimmed) {
                normalizedLines.append(trimmed)
                seenRecent.insert(trimmed)
                if seenRecent.count > 48 {
                    seenRecent.removeAll(keepingCapacity: true)
                }
            }
        }

        var text = normalizedLines.joined(separator: "\n")
        var redactedCount = 0

        if redactSecrets {
            for rule in rules {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else {
                    continue
                }
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)
                if !matches.isEmpty {
                    redactedCount += matches.count
                    if rule.label == "SECRET_ASSIGNMENT" {
                        text = regex.stringByReplacingMatches(
                            in: text,
                            options: [],
                            range: nsRange,
                            withTemplate: "$1=[REDACTED:SECRET]"
                        )
                    } else if rule.label == "BEARER_TOKEN" {
                        text = regex.stringByReplacingMatches(
                            in: text,
                            options: [],
                            range: nsRange,
                            withTemplate: "Bearer [REDACTED:TOKEN]"
                        )
                    } else {
                        text = regex.stringByReplacingMatches(
                            in: text,
                            options: [],
                            range: nsRange,
                            withTemplate: "[REDACTED:\(rule.label)]"
                        )
                    }
                }
            }
        }

        let urls = extractURLs(from: text)
        let tags = inferTags(from: text, urls: urls)
        return SanitizedTextResult(
            cleanText: text,
            redactedCount: redactedCount,
            extractedURLs: urls,
            detectedTags: tags
        )
    }

    public static func extractURLs(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var urls: [String] = []
        var seen = Set<String>()
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                let s = url.absoluteString
                if seen.insert(s).inserted {
                    urls.append(s)
                }
            }
        }
        return urls
    }

    public static func inferTags(from text: String, urls: [String]) -> [String] {
        let lower = text.lowercased()
        var tags: [String] = []
        if lower.contains("error:") || lower.contains("exception") || lower.contains("fatal") || lower.contains("traceback") || lower.contains("stack trace") {
            tags.append("error")
        }
        if lower.contains("func ") || lower.contains("import ") || lower.contains("const ") || lower.contains("struct ") || lower.contains("def ") || lower.contains("return ") {
            tags.append("code")
        }
        if lower.contains("invoice") || lower.contains("subtotal") || lower.contains("total due") || lower.contains("receipt") {
            tags.append("finance")
        }
        if lower.contains("zoom") || lower.contains("agenda") || lower.contains("action items") || lower.contains("q1") || lower.contains("q2") || lower.contains("q3") || lower.contains("q4") {
            tags.append("meeting")
        }
        if !urls.isEmpty {
            tags.append("web")
        }
        if lower.contains("[redacted:") {
            tags.append("redacted")
        }
        return tags
    }
}
