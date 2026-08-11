import Foundation

/// Removes common credential and personal-identifier shapes before diagnostic
/// text leaves the app. Callers should still prefer bounded, typed error cases
/// over arbitrary SDK or system messages.
public enum DiagnosticSanitizer {
    private static let maximumLength = 500

    public static func sanitizedError(_ value: String?) -> String? {
        guard let value else { return nil }
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return nil }

        result = replacing(
            pattern: #"(?i)\b(token|authorization|credential|password|secret)\b\s*[:=]\s*[^\s,;]+"#,
            in: result,
            with: "$1=<redacted>"
        )
        result = replacing(
            pattern: #"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]+"#,
            in: result,
            with: "$1 <redacted>"
        )
        result = replacing(
            pattern: #"(?i)([a-z][a-z0-9+.-]*://[^\s?#]+)\?[^\s#]*"#,
            in: result,
            with: "$1?<redacted>"
        )
        result = replacing(
            pattern: #"/Users/[^/\s]+"#,
            in: result,
            with: "/Users/<redacted>"
        )
        result = replacing(
            pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: result,
            with: "<redacted-email>",
            options: [.caseInsensitive]
        )
        result = replacing(
            pattern: #"\b[A-Za-z0-9_-]{32,}\b"#,
            in: result,
            with: "<redacted-value>"
        )

        if result.count > maximumLength {
            result = String(result.prefix(maximumLength)) + "…"
        }
        return result
    }

    /// Preserves the public URL location while removing user info, query items,
    /// and fragments that could contain tracking or authorization values.
    public static func sanitizedPublicURL(_ value: String?) -> String? {
        guard let value,
            var components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            components.host != nil
        else { return nil }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
