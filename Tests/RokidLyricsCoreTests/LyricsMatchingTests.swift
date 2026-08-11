import XCTest
@testable import RokidLyricsCore

final class LyricsMatchingTests: XCTestCase {
    private let scorer = LyricsMatchScorer()

    func testExactSongAndArtistMatch() {
        let result = scorer.score(
            query: LyricsQuery(title: "Synthetic Song", artist: "Test Artist"),
            candidate: candidate(title: "Synthetic Song", artist: "Test Artist")
        )

        XCTAssertEqual(result.score, 0.95, accuracy: 0.000_1)
        XCTAssertEqual(result.breakdown.titleSimilarity, 1)
        XCTAssertEqual(result.breakdown.artistSimilarity, 1)
    }

    func testUnrelatedArtistIsRejectedDespiteExactTitle() {
        let selection = scorer.selectBest(
            query: LyricsQuery(title: "Synthetic Song", artist: "Test Artist"),
            candidates: [candidate(title: "Synthetic Song", artist: "Unrelated Ensemble")]
        )

        guard case .noMatch = selection else {
            return XCTFail("Expected unrelated artist to be rejected")
        }
    }

    func testFeaturedArtistSyntaxMatchesConservatively() {
        let result = scorer.score(
            query: LyricsQuery(
                title: "Synthetic Song (feat. Guest)",
                artist: "Test Artist feat Guest"
            ),
            candidate: candidate(title: "Synthetic Song", artist: "Test Artist")
        )

        XCTAssertGreaterThan(result.score, 0.85)
        XCTAssertLessThan(result.score, 0.95)
    }

    func testCanonicalUnicodeCompositionMatches() {
        let decomposed = "Cafe\u{301} Test"
        let result = scorer.score(
            query: LyricsQuery(title: decomposed, artist: "Élodie"),
            candidate: candidate(title: "Café Test", artist: "E\u{301}lodie")
        )

        XCTAssertEqual(result.breakdown.titleSimilarity, 1)
        XCTAssertEqual(result.breakdown.artistSimilarity, 1)
    }

    func testCJKMetadataIsPreservedAndMatched() {
        let cases = [
            ("日本語の曲", "日本語歌手"),
            ("中文歌曲", "中文歌手"),
            ("한국어 노래", "한국어 가수"),
        ]

        for (title, artist) in cases {
            let result = scorer.score(
                query: LyricsQuery(title: title, artist: artist),
                candidate: candidate(title: title, artist: artist)
            )
            XCTAssertEqual(result.score, 0.95, accuracy: 0.000_1)
        }
    }

    func testWidthNormalizationSupportsFullWidthLatin() {
        let normalizer = LyricsMetadataNormalizer()

        XCTAssertEqual(normalizer.normalizedText("ＴＥＳＴ　ＳＯＮＧ"), "test song")
    }

    func testDifferentExplicitVersionsArePenalized() {
        let exact = scorer.score(
            query: LyricsQuery(title: "Synthetic Song (Live)", artist: "Test Artist"),
            candidate: candidate(title: "Synthetic Song (Live)", artist: "Test Artist")
        )
        let differentVersion = scorer.score(
            query: LyricsQuery(title: "Synthetic Song (Live)", artist: "Test Artist"),
            candidate: candidate(title: "Synthetic Song (Acoustic)", artist: "Test Artist")
        )

        XCTAssertLessThan(differentVersion.score, exact.score)
        XCTAssertEqual(differentVersion.breakdown.titleSimilarity, 0.74)
    }

    func testArbitraryParentheticalTitleIsNotDiscarded() {
        let normalizer = LyricsMetadataNormalizer()
        let normalized = normalizer.normalize(
            title: "Synthetic Song (Blue)",
            artist: "Test Artist"
        )

        XCTAssertEqual(normalized.coreTitle, "synthetic song (blue)")
        XCTAssertNil(normalized.titleVersion)
    }

    func testAlbumAndDurationImproveScore() {
        let query = LyricsQuery(
            title: "Synthetic Song",
            artist: "Test Artist",
            album: "Synthetic Album",
            duration: 180
        )
        let result = scorer.score(
            query: query,
            candidate: candidate(
                title: "Synthetic Song",
                artist: "Test Artist",
                album: "Synthetic Album",
                duration: 181
            )
        )

        XCTAssertEqual(result.score, 1, accuracy: 0.000_1)
    }

    func testAmbiguousResultsAreSurfacedInsteadOfGuessed() {
        let query = LyricsQuery(title: "Synthetic Song", artist: "Test Artist")
        let candidates = [
            candidate(id: "a", title: "Synthetic Song", artist: "Test Artist"),
            candidate(id: "b", title: "Synthetic Song", artist: "Test Artist"),
        ]

        guard
            case let .ambiguous(results) = scorer.selectBest(
                query: query,
                candidates: candidates
            )
        else {
            return XCTFail("Expected ambiguity")
        }
        XCTAssertEqual(results.map(\.candidate.id), ["a", "b"])
    }

    private func candidate(
        id: String = "candidate",
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) -> LyricsCandidate {
        LyricsCandidate(
            id: id,
            providerName: "Test Provider",
            trackTitle: title,
            artistName: artist,
            albumName: album,
            duration: duration,
            synchronizedLyrics: "[00:01.00]First test line"
        )
    }
}
