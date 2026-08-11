import Foundation
import RokidLyricsCore
import Testing
@testable import RokidLyricsServices

@Suite("Rokid CustomView payload encoder")
struct RokidCustomViewPayloadTests {
    @Test("open payload uses only the verified layout and text nodes")
    func openPayloadShape() throws {
        let payload = try RokidCustomViewPayloadEncoder().payload(for: displayModel())
        let root = try #require(jsonObject(payload.openJSON) as? [String: Any])
        let props = try #require(root["props"] as? [String: String])
        let children = try #require(root["children"] as? [[String: Any]])

        #expect(root["type"] as? String == "LinearLayout")
        #expect(props["layout_width"] == "match_parent")
        #expect(props["orientation"] == "vertical")
        #expect(children.count == 4)
        #expect(children.allSatisfy { $0["type"] as? String == "TextView" })

        let ids = children.compactMap { ($0["props"] as? [String: String])?["id"] }
        #expect(
            ids == [
                "rokid_lyrics_metadata",
                "rokid_lyrics_previous",
                "rokid_lyrics_active",
                "rokid_lyrics_next",
            ])
    }

    @Test("Unicode and JSON control characters round-trip without interpolation")
    func unicodeAndEscaping() throws {
        let model = GlassesDisplayModel(
            trackTitle: "テスト曲 \"A\"",
            artist: "歌手\\作者",
            previousLine: "日本語",
            activeLine: "中文\n第二行",
            nextLine: "한국어",
            status: .displayingLyrics
        )
        let payload = try RokidCustomViewPayloadEncoder().payload(for: model)
        let root = try #require(jsonObject(payload.openJSON) as? [String: Any])
        let children = try #require(root["children"] as? [[String: Any]])
        let props = children.compactMap { $0["props"] as? [String: String] }

        #expect(props[0]["text"] == "テスト曲 \"A\" — 歌手\\作者")
        #expect(props[1]["text"] == "日本語")
        #expect(props[2]["text"] == "中文\n第二行")
        #expect(props[3]["text"] == "한국어")
    }

    @Test("line preferences clear hidden stable nodes")
    func hiddenLinesAreCleared() throws {
        let model = GlassesDisplayModel(
            trackTitle: "Synthetic Song",
            artist: "Test Artist",
            previousLine: "Previous test line",
            activeLine: "Current test line",
            nextLine: "Next test line",
            status: .displayingLyrics,
            preferences: GlassesDisplayPreferences(
                fontScale: 1,
                visibleLineCount: 1,
                showPreviousLine: true,
                showNextLine: true
            )
        )
        let payload = try RokidCustomViewPayloadEncoder().payload(for: model)
        let updates = try #require(jsonObject(payload.updateJSON) as? [[String: Any]])
        let pairs: [(String, [String: String])] = updates.compactMap { item in
            guard let id = item["id"] as? String,
                let props = item["props"] as? [String: String]
            else { return nil }
            return (id, props)
        }
        let byID = Dictionary(uniqueKeysWithValues: pairs)

        #expect(byID["rokid_lyrics_previous"]?["text"] == "")
        #expect(byID["rokid_lyrics_active"]?["text"] == "Current test line")
        #expect(byID["rokid_lyrics_next"]?["text"] == "")
    }

    @Test("font scale updates verified sp properties")
    func fontScale() throws {
        let model = GlassesDisplayModel(
            trackTitle: "Synthetic Song",
            artist: "Test Artist",
            activeLine: "Current test line",
            status: .displayingLyrics,
            preferences: GlassesDisplayPreferences(fontScale: 1.5)
        )
        let payload = try RokidCustomViewPayloadEncoder().payload(for: model)
        let updates = try #require(jsonObject(payload.updateJSON) as? [[String: Any]])
        let active = try #require(updates.first { $0["id"] as? String == "rokid_lyrics_active" })
        let props = try #require(active["props"] as? [String: String])

        #expect(props == ["text": "Current test line", "textSize": "33sp"])
    }

    @Test("progress-only changes do not create display traffic")
    func progressIsNotEncoded() throws {
        let encoder = RokidCustomViewPayloadEncoder()
        let first = try encoder.payload(for: displayModel(progress: 0.1))
        let second = try encoder.payload(for: displayModel(progress: 0.9))

        #expect(first == second)
    }

    @Test("abstract vertical position uses only verified gravity values")
    func verticalPosition() throws {
        let encoder = RokidCustomViewPayloadEncoder()
        let positions: [(Double, String)] = [
            (0, "top"),
            (0.5, "center_vertical"),
            (1, "bottom"),
        ]

        for (position, expectedGravity) in positions {
            let model = GlassesDisplayModel(
                trackTitle: "Synthetic Song",
                artist: "Test Artist",
                activeLine: "Current test line",
                status: .displayingLyrics,
                preferences: GlassesDisplayPreferences(verticalPosition: position)
            )
            let payload = try encoder.payload(for: model)
            let root = try #require(jsonObject(payload.openJSON) as? [String: Any])
            let props = try #require(root["props"] as? [String: String])
            #expect(props["gravity"] == expectedGravity)
            #expect(payload.layoutIdentifier == expectedGravity)
        }
    }

    private func displayModel(progress: Double = 0.5) -> GlassesDisplayModel {
        GlassesDisplayModel(
            trackTitle: "Synthetic Song",
            artist: "Test Artist",
            previousLine: "Previous test line",
            activeLine: "Current test line",
            nextLine: "Next test line",
            progress: progress,
            status: .displayingLyrics
        )
    }

    private func jsonObject(_ string: String) throws -> Any {
        let data = try #require(string.data(using: .utf8))
        return try JSONSerialization.jsonObject(with: data)
    }
}
