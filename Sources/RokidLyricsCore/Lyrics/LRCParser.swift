import Foundation

/// Parses common LRC syntax without treating malformed input as fatal.
///
/// Supported timestamps include `m:ss`, `mm:ss.xx`, `mm:ss.xxx`, and
/// `h:mm:ss.xxx`. Multiple leading timestamps produce one line per timestamp.
/// Timestamped empty lines are intentionally preserved.
public struct LRCParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> LyricDocument {
        var parsedLines: [LyricLine] = []
        var metadata: [String: String] = [:]
        var embeddedOffset: TimeInterval = 0
        var sourceOrder = 0

        source.enumerateLines { rawLine, _ in
            let parsed = parseLeadingTags(in: rawLine)

            for tag in parsed.nonTimestampTags {
                guard let separator = tag.firstIndex(of: ":") else { continue }
                let key = tag[..<separator]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let value = tag[tag.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                metadata[key] = value

                if key == "offset", let milliseconds = Double(value) {
                    embeddedOffset = milliseconds / 1_000
                }
            }

            guard !parsed.timestamps.isEmpty else { return }
            let lyricText = parsed.remainder
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for timestamp in parsed.timestamps {
                parsedLines.append(
                    LyricLine(id: sourceOrder, timestamp: timestamp, text: lyricText)
                )
                sourceOrder += 1
            }
        }

        return LyricDocument(
            lines: parsedLines,
            metadata: metadata,
            embeddedOffsetSeconds: embeddedOffset
        )
    }

    private func parseLeadingTags(
        in line: String
    ) -> (timestamps: [TimeInterval], nonTimestampTags: [String], remainder: String) {
        var cursor = line.startIndex
        var timestamps: [TimeInterval] = []
        var otherTags: [String] = []

        while cursor < line.endIndex, line[cursor] == "[" {
            guard let closingBracket = line[cursor...].firstIndex(of: "]") else { break }
            let contentStart = line.index(after: cursor)
            let tag = String(line[contentStart..<closingBracket])

            if let timestamp = parseTimestamp(tag) {
                timestamps.append(timestamp)
            } else {
                otherTags.append(tag)
            }

            cursor = line.index(after: closingBracket)
        }

        return (timestamps, otherTags, String(line[cursor...]))
    }

    private func parseTimestamp(_ rawValue: String) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3 else { return nil }

        if components.count == 2 {
            guard
                let minutes = nonnegativeInteger(components[0]),
                let seconds = secondsComponent(components[1])
            else {
                return nil
            }
            return (Double(minutes) * 60) + seconds
        }

        guard
            let hours = nonnegativeInteger(components[0]),
            let minutes = nonnegativeInteger(components[1]),
            minutes < 60,
            let seconds = secondsComponent(components[2])
        else {
            return nil
        }
        return (Double(hours) * 3_600) + (Double(minutes) * 60) + seconds
    }

    private func nonnegativeInteger(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber), let result = Int(value) else {
            return nil
        }
        return result
    }

    private func secondsComponent(_ value: Substring) -> TimeInterval? {
        guard !value.isEmpty else { return nil }

        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { return nil }
        guard let wholeSeconds = nonnegativeInteger(pieces[0]), wholeSeconds < 60 else {
            return nil
        }

        guard pieces.count == 2 else { return Double(wholeSeconds) }
        let fraction = pieces[1]
        guard
            (1...3).contains(fraction.count),
            fraction.allSatisfy(\.isNumber),
            let fractionalValue = Int(fraction)
        else {
            return nil
        }

        let denominator = pow(10, Double(fraction.count))
        return Double(wholeSeconds) + (Double(fractionalValue) / denominator)
    }
}

