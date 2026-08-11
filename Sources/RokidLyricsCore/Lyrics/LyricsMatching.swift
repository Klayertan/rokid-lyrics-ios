import Foundation

public struct NormalizedTrackMetadata: Equatable, Sendable {
    public let title: String
    public let coreTitle: String
    public let titleVersion: String?
    public let artist: String
    public let coreArtist: String
    public let album: String?

    public init(
        title: String,
        coreTitle: String,
        titleVersion: String?,
        artist: String,
        coreArtist: String,
        album: String?
    ) {
        self.title = title
        self.coreTitle = coreTitle
        self.titleVersion = titleVersion
        self.artist = artist
        self.coreArtist = coreArtist
        self.album = album
    }
}

/// Conservative metadata normalization used before lyrics matching.
///
/// It performs canonical Unicode composition, case/width folding, whitespace
/// collapse, and limited handling of explicit featured-artist and version
/// suffixes. It intentionally does not remove accents, transliterate CJK text,
/// or discard arbitrary parenthetical text.
public struct LyricsMetadataNormalizer: Sendable {
    public init() {}

    public func normalize(
        title: String,
        artist: String,
        album: String? = nil
    ) -> NormalizedTrackMetadata {
        let normalizedTitle = normalizedText(title)
        let normalizedArtist = normalizedText(artist)
        let normalizedAlbum = album.map(normalizedText).flatMap { $0.isEmpty ? nil : $0 }
        let versionResult = removingVersionSuffix(from: normalizedTitle)

        return NormalizedTrackMetadata(
            title: normalizedTitle,
            coreTitle: removingFeaturedSuffix(from: versionResult.core),
            titleVersion: versionResult.version,
            artist: normalizedArtist,
            coreArtist: removingFeaturedSuffix(from: normalizedArtist),
            album: normalizedAlbum
        )
    }

    public func normalizedText(_ input: String) -> String {
        let canonical = input.precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )

        var punctuationNormalized = ""
        punctuationNormalized.reserveCapacity(canonical.count)
        for character in canonical {
            switch character {
            case "‘", "’", "ʼ": punctuationNormalized.append("'")
            case "–", "—", "−": punctuationNormalized.append("-")
            default: punctuationNormalized.append(character)
            }
        }

        return punctuationNormalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removingFeaturedSuffix(from value: String) -> String {
        var result = value

        if let suffix = trailingBracketedContent(in: result), isFeaturedClause(suffix.content) {
            result = String(result[..<suffix.openingIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let markers = [" feat. ", " feat ", " ft. ", " ft ", " featuring "]
        var earliestMarker: String.Index?
        for marker in markers {
            if let range = result.range(of: marker) {
                if let existingMarker = earliestMarker {
                    if range.lowerBound < existingMarker {
                        earliestMarker = range.lowerBound
                    }
                } else {
                    earliestMarker = range.lowerBound
                }
            }
        }
        if let earliestMarker {
            result = String(result[..<earliestMarker])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func removingVersionSuffix(from value: String) -> (core: String, version: String?) {
        if let suffix = trailingBracketedContent(in: value), isVersionDescriptor(suffix.content) {
            let core = String(value[..<suffix.openingIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (core, suffix.content)
        }

        if let separator = value.range(of: " - ", options: .backwards) {
            let suffix = String(value[separator.upperBound...])
            if isVersionDescriptor(suffix) {
                return (
                    String(value[..<separator.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    suffix
                )
            }
        }
        return (value, nil)
    }

    private func trailingBracketedContent(
        in value: String
    ) -> (openingIndex: String.Index, content: String)? {
        guard let final = value.last, final == ")" || final == "]" else { return nil }
        let opening: Character = final == ")" ? "(" : "["
        guard let openingIndex = value.lastIndex(of: opening) else { return nil }
        let contentStart = value.index(after: openingIndex)
        let contentEnd = value.index(before: value.endIndex)
        guard contentStart <= contentEnd else { return nil }
        let content = String(value[contentStart..<contentEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (openingIndex, content)
    }

    private func isFeaturedClause(_ content: String) -> Bool {
        ["feat. ", "feat ", "ft. ", "ft ", "featuring "]
            .contains { content.hasPrefix($0) }
    }

    private func isVersionDescriptor(_ content: String) -> Bool {
        let markers = [
            "acoustic", "demo", "edit", "instrumental", "karaoke", "live",
            "mix", "mono", "radio", "remaster", "remastered", "slowed",
            "sped up", "stereo", "version"
        ]
        return markers.contains { content.contains($0) }
    }
}

public struct LyricsMatchBreakdown: Codable, Equatable, Sendable {
    public let titleSimilarity: Double
    public let artistSimilarity: Double
    public let albumSimilarity: Double?
    public let durationSimilarity: Double?
    public let totalScore: Double
}

public struct ScoredLyricsCandidate: Equatable, Sendable {
    public let candidate: LyricsCandidate
    public let breakdown: LyricsMatchBreakdown

    public var score: Double { breakdown.totalScore }
}

public enum LyricsMatchSelection: Equatable, Sendable {
    case match(ScoredLyricsCandidate)
    case ambiguous([ScoredLyricsCandidate])
    case noMatch([ScoredLyricsCandidate])
}

/// Deterministic, provider-neutral scoring.
///
/// Criteria and maximum weights:
/// - title: 0.60
/// - artist: 0.35
/// - album (when both sides provide it): 0.03
/// - duration (when both sides provide it): 0.02
///
/// Exact title/artist metadata therefore scores 0.95 even when optional data is
/// absent. Version conflicts are retained and penalized instead of being erased.
public struct LyricsMatchScorer: Sendable {
    public let minimumScore: Double
    public let ambiguityDelta: Double
    private let normalizer: LyricsMetadataNormalizer

    public init(
        minimumScore: Double = 0.72,
        ambiguityDelta: Double = 0.025,
        normalizer: LyricsMetadataNormalizer = LyricsMetadataNormalizer()
    ) {
        self.minimumScore = minimumScore
        self.ambiguityDelta = ambiguityDelta
        self.normalizer = normalizer
    }

    public func score(
        query: LyricsQuery,
        candidate: LyricsCandidate
    ) -> ScoredLyricsCandidate {
        let queryMetadata = normalizer.normalize(
            title: query.title,
            artist: query.artist,
            album: query.album
        )
        let candidateMetadata = normalizer.normalize(
            title: candidate.trackTitle,
            artist: candidate.artistName,
            album: candidate.albumName
        )

        let title = titleSimilarity(queryMetadata, candidateMetadata)
        let artist = artistSimilarity(queryMetadata, candidateMetadata)
        let album = optionalTextSimilarity(queryMetadata.album, candidateMetadata.album)
        let duration = durationSimilarity(query.duration, candidate.duration)
        let total = min(
            (title * 0.60)
                + (artist * 0.35)
                + ((album ?? 0) * 0.03)
                + ((duration ?? 0) * 0.02),
            1
        )

        return ScoredLyricsCandidate(
            candidate: candidate,
            breakdown: LyricsMatchBreakdown(
                titleSimilarity: title,
                artistSimilarity: artist,
                albumSimilarity: album,
                durationSimilarity: duration,
                totalScore: total
            )
        )
    }

    public func rank(
        query: LyricsQuery,
        candidates: [LyricsCandidate]
    ) -> [ScoredLyricsCandidate] {
        candidates
            .map { score(query: query, candidate: $0) }
            .sorted {
                if $0.score == $1.score { return $0.candidate.id < $1.candidate.id }
                return $0.score > $1.score
            }
    }

    public func selectBest(
        query: LyricsQuery,
        candidates: [LyricsCandidate]
    ) -> LyricsMatchSelection {
        let ranked = rank(query: query, candidates: candidates)
        guard let best = ranked.first, best.score >= minimumScore else {
            return .noMatch(ranked)
        }

        let plausible = ranked.filter {
            $0.score >= minimumScore && best.score - $0.score <= ambiguityDelta
        }
        if plausible.count > 1 { return .ambiguous(plausible) }
        return .match(best)
    }

    private func titleSimilarity(
        _ lhs: NormalizedTrackMetadata,
        _ rhs: NormalizedTrackMetadata
    ) -> Double {
        if lhs.title == rhs.title { return 1 }
        if lhs.coreTitle == rhs.coreTitle {
            switch (lhs.titleVersion, rhs.titleVersion) {
            case let (left?, right?) where left == right: return 0.96
            case (_?, _?): return 0.74
            case (nil, nil): return 0.96
            default: return 0.90
            }
        }
        return fuzzySimilarity(lhs.coreTitle, rhs.coreTitle)
    }

    private func artistSimilarity(
        _ lhs: NormalizedTrackMetadata,
        _ rhs: NormalizedTrackMetadata
    ) -> Double {
        if lhs.artist == rhs.artist { return 1 }
        if lhs.coreArtist == rhs.coreArtist { return 0.94 }
        return fuzzySimilarity(lhs.coreArtist, rhs.coreArtist)
    }

    private func optionalTextSimilarity(_ lhs: String?, _ rhs: String?) -> Double? {
        guard let lhs, let rhs else { return nil }
        if lhs == rhs { return 1 }
        return fuzzySimilarity(lhs, rhs)
    }

    private func durationSimilarity(
        _ lhs: TimeInterval?,
        _ rhs: TimeInterval?
    ) -> Double? {
        guard let lhs, let rhs, lhs > 0, rhs > 0 else { return nil }
        switch abs(lhs - rhs) {
        case ...2: return 1
        case ...5: return 0.75
        case ...10: return 0.35
        default: return 0
        }
    }

    private func fuzzySimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let tokenScore = tokenDiceCoefficient(lhs, rhs)
        let characterScore = characterSimilarity(lhs, rhs) * 0.90
        let result = max(tokenScore, characterScore)
        return result >= 0.45 ? result : 0
    }

    private func tokenDiceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        let leftTokens = Set(tokens(in: lhs))
        let rightTokens = Set(tokens(in: rhs))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let overlap = leftTokens.intersection(rightTokens).count
        return (2 * Double(overlap)) / Double(leftTokens.count + rightTokens.count)
    }

    private func tokens(in value: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in value {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func characterSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs.prefix(256))
        let right = Array(rhs.prefix(256))
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }
            previous = current
        }

        let maximumLength = max(left.count, right.count)
        return 1 - (Double(previous[right.count]) / Double(maximumLength))
    }
}
