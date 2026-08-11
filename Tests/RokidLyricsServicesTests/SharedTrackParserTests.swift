import Foundation
import Testing
@testable import RokidLyricsServices

@Suite("Shared track parser")
struct SharedTrackParserTests {
    @Test("explicit metadata is accepted")
    func explicitFields() {
        let draft = SharedTrackParser.parse(
            text: nil,
            url: URL(string: "https://music.example/item"),
            explicitTitle: "Test Song",
            explicitArtist: "Test Artist"
        )

        #expect(draft.title == "Test Song")
        #expect(draft.artist == "Test Artist")
        #expect(!draft.requiresConfirmation)
    }

    @Test("two clean lines are parsed but still require confirmation")
    func twoLines() {
        let draft = SharedTrackParser.parse(
            text: "Test Song\nTest Artist\nhttps://music.example/item",
            url: URL(string: "https://music.example/item")
        )

        #expect(draft.title == "Test Song")
        #expect(draft.artist == "Test Artist")
        #expect(draft.requiresConfirmation)
    }

    @Test("a conservative dash pattern is parsed")
    func dashPattern() {
        let draft = SharedTrackParser.parse(text: "Test Song — Test Artist", url: nil)

        #expect(draft.title == "Test Song")
        #expect(draft.artist == "Test Artist")
        #expect(draft.parseQuality == .conservativeTextPattern)
    }

    @Test("URL-only shares do not invent metadata")
    func urlOnly() {
        let draft = SharedTrackParser.parse(
            text: "https://music.example/item",
            url: URL(string: "https://music.example/item")
        )

        #expect(draft.title == nil)
        #expect(draft.artist == nil)
        #expect(draft.requiresConfirmation)
    }

    @Test("non-web URLs are rejected")
    func unsafeScheme() {
        let draft = SharedTrackParser.parse(
            text: nil,
            url: URL(string: "youtube-music-private://item")
        )

        #expect(draft.url == nil)
    }

    @Test("CJK metadata is preserved")
    func cjkText() {
        let draft = SharedTrackParser.parse(text: "テスト曲\nテスト歌手", url: nil)

        #expect(draft.title == "テスト曲")
        #expect(draft.artist == "テスト歌手")
    }
}
