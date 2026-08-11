import Testing
@testable import RokidLyricsServices

@Suite("Shared track App Group resolver")
struct SharedTrackAppGroupResolverTests {
    @Test("uses the configured App Group from the target Info dictionary")
    func configuredIdentifier() {
        let result = SharedTrackAppGroupResolver.resolve(
            infoDictionary: [
                SharedTrackAppGroupResolver.infoDictionaryKey: "group.dev.example.rokidlyrics"
            ]
        )

        #expect(result == "group.dev.example.rokidlyrics")
    }

    @Test("trims surrounding configuration whitespace")
    func trimsWhitespace() {
        let result = SharedTrackAppGroupResolver.resolve(
            infoDictionary: [
                SharedTrackAppGroupResolver.infoDictionaryKey: "  group.dev.example.shared\n"
            ]
        )

        #expect(result == "group.dev.example.shared")
    }

    @Test("uses the supplied fallback when the Info key is absent")
    func missingConfiguration() {
        let result = SharedTrackAppGroupResolver.resolve(
            infoDictionary: nil,
            fallbackIdentifier: "group.test.fallback"
        )

        #expect(result == "group.test.fallback")
    }

    @Test("rejects unresolved build settings and invalid group identifiers")
    func invalidConfiguration() {
        let unresolved = SharedTrackAppGroupResolver.resolve(
            infoDictionary: [
                SharedTrackAppGroupResolver.infoDictionaryKey: "$(ROKID_LYRICS_APP_GROUP)"
            ],
            fallbackIdentifier: "group.test.fallback"
        )
        let invalid = SharedTrackAppGroupResolver.resolve(
            infoDictionary: [
                SharedTrackAppGroupResolver.infoDictionaryKey: "com.example.not-an-app-group"
            ],
            fallbackIdentifier: "group.test.fallback"
        )

        #expect(unresolved == "group.test.fallback")
        #expect(invalid == "group.test.fallback")
    }
}
