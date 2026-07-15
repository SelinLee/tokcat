import Foundation

/// Shared UI formatting for raw model identifiers from agent / proxy logs.
///
/// Raw values are often vendor-prefixed or path-qualified, e.g.
/// `anthropic/claude-sonnet-5`, `claude-sonnet5`, `us.anthropic.claude-opus-4-5-v1:0`.
/// Prefer the concise core name when a known pattern matches; otherwise fall
/// back to the last path segment (legacy behavior).
public enum ModelNameFormatting {
    /// Compact label for menus, dashboards, and pet copy.
    public static func shortDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        let leaf = pathLeaf(trimmed)
        let normalized = dropInferenceProfilePrefix(leaf)

        if let core = extractClaudeFamilyName(from: normalized) {
            return core
        }

        return stripTrailingMetadata(normalized)
    }

    // MARK: - Internals

    /// Last `/` (or `\`) segment — original short-name behavior.
    public static func pathLeaf(_ model: String) -> String {
        if let last = model.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last {
            let value = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? model : value
        }
        return model
    }

    /// `us.anthropic.claude-…` / `anthropic.claude-…` → start at `claude…`.
    private static func dropInferenceProfilePrefix(_ model: String) -> String {
        let lower = model.lowercased()
        guard let range = lower.range(of: "claude") else { return model }
        // Only rewrite when `claude` is after a dotted vendor/region prefix.
        if range.lowerBound > lower.startIndex {
            let prefix = lower[..<range.lowerBound]
            if prefix.contains(".") {
                let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let start = model.index(model.startIndex, offsetBy: offset)
                return String(model[start...])
            }
        }
        return model
    }

    /// Pull sonnet / opus / haiku (+ version trail) out of Claude-style ids.
    private static func extractClaudeFamilyName(from model: String) -> String? {
        let patterns = [
            // claude-sonnet5 / claude-sonnet-4-5 / claude_opus_4.5 / Claude-Haiku-4.5-...
            #"^(?i)claude[-_. ]+((?:sonnet|opus|haiku)[a-z0-9._-]*)$"#,
            // claude-3-5-sonnet / claude-3-opus-20240229 / claude-3.5-haiku-...
            #"^(?i)claude[-_. ]+((?:\d+(?:[._-]\d+)*)[-_. ]?(?:sonnet|opus|haiku)[a-z0-9._-]*)$"#
        ]

        for pattern in patterns {
            if let match = firstMatch(in: model, pattern: pattern, group: 1) {
                return stripTrailingMetadata(match)
            }
        }

        // Bedrock-style leftovers still containing the family token.
        if let match = firstMatch(
            in: model,
            pattern: #"(?i)\b((?:sonnet|opus|haiku)[a-z0-9._-]*)\b"#,
            group: 1
        ), model.lowercased().contains("claude") {
            return stripTrailingMetadata(match)
        }

        return nil
    }

    /// Drop dated / profile suffixes that add noise without identifying the model.
    private static func stripTrailingMetadata(_ model: String) -> String {
        var value = model
        let suffixPatterns = [
            #"(?i)[-_]v\d+(?:[:.]\d+)?$"#,
            #"(?i)[-_]\d{8}$"#
        ]
        for pattern in suffixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
            }
        }
        return value.isEmpty ? model : value
    }

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: full),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text)
        else {
            return nil
        }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
