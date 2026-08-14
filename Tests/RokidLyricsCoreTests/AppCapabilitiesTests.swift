import Testing

@testable import RokidLyricsCore

@Suite("App capabilities resolver")
struct AppCapabilitiesTests {
    @Test("full-capability build resolves every capability available")
    func fullCapabilityBuild() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.buildModeInfoDictionaryKey: "mock"
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )

        #expect(result.buildMode == "mock")
        #expect(result.personalTeamMode == false)
        #expect(result.shazamRecognitionAvailable == true)
        #expect(result.shareExtensionAvailable == true)
        #expect(result.appGroupAvailable == true)
        #expect(result.rokidHardwareAvailable == false)
    }

    @Test("Personal Team build selects manual-only capabilities")
    func personalCapabilitySelection() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.buildModeInfoDictionaryKey: "personal",
                AppCapabilitiesResolver.personalTeamModeInfoDictionaryKey: "YES",
                AppCapabilitiesResolver.shazamAvailableInfoDictionaryKey: "YES",
                AppCapabilitiesResolver.shareExtensionAvailableInfoDictionaryKey: "NO",
                AppCapabilitiesResolver.appGroupAvailableInfoDictionaryKey: "NO",
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )

        #expect(result.buildMode == "personal")
        #expect(result.personalTeamMode == true)
        #expect(result.shazamRecognitionAvailable == true)
        #expect(result.shareExtensionAvailable == false)
        #expect(result.appGroupAvailable == false)
        #expect(result.rokidHardwareAvailable == false)
    }

    @Test("Shazam is unavailable when the configuration flag is on but the build was not compiled with it")
    func shazamFlagOnButNotCompiled() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.shazamAvailableInfoDictionaryKey: "YES"
            ],
            shazamCompiled: false,
            rokidHardwareCompiled: false
        )

        #expect(result.shazamRecognitionAvailable == false)
    }

    @Test("Shazam is unavailable when compiled in but the configuration flag disables it")
    func shazamCompiledButFlagOff() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.shazamAvailableInfoDictionaryKey: "NO"
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )

        #expect(result.shazamRecognitionAvailable == false)
    }

    @Test("Rokid hardware availability reflects only the compiled flag")
    func rokidHardwareReflectsCompiledFlag() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: nil,
            shazamCompiled: false,
            rokidHardwareCompiled: true
        )

        #expect(result.rokidHardwareAvailable == true)
    }

    @Test("unresolved or missing build-mode settings fall back to mock")
    func buildModeSelectionFallback() {
        let missing = AppCapabilitiesResolver.resolve(
            infoDictionary: nil,
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )
        let unresolved = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.buildModeInfoDictionaryKey: "$(ROKID_LYRICS_BUILD_MODE)"
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )
        let blank = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.buildModeInfoDictionaryKey: "   "
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )

        #expect(missing.buildMode == "mock")
        #expect(unresolved.buildMode == "mock")
        #expect(blank.buildMode == "mock")
    }

    @Test("build mode is trimmed and lowercased")
    func buildModeNormalization() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.buildModeInfoDictionaryKey: "  Personal\n"
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: false
        )

        #expect(result.buildMode == "personal")
    }

    @Test(
        "boolean flags accept common truthy/falsy string spellings",
        arguments: [
            ("YES", true), ("yes", true), ("true", true), ("1", true),
            ("NO", false), ("no", false), ("false", false), ("0", false),
        ]
    )
    func flagStringSpellings(spelling: String, expected: Bool) {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.appGroupAvailableInfoDictionaryKey: spelling
            ],
            shazamCompiled: false,
            rokidHardwareCompiled: false
        )

        #expect(result.appGroupAvailable == expected)
    }

    @Test("an unresolved build-setting placeholder falls back to the default rather than being treated as falsy")
    func flagFallbackOnUnresolvedPlaceholder() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                AppCapabilitiesResolver.appGroupAvailableInfoDictionaryKey: "$(ROKID_LYRICS_APP_GROUP_AVAILABLE)"
            ],
            shazamCompiled: false,
            rokidHardwareCompiled: false
        )

        #expect(result.appGroupAvailable == true)
    }

    @Test("resolved capabilities expose no fields beyond the documented, non-sensitive set")
    func capabilityReportSanitization() {
        let result = AppCapabilitiesResolver.resolve(
            infoDictionary: [
                "TeamID": "ABCDE12345",
                "AppleAccountEmail": "someone@example.com",
            ],
            shazamCompiled: true,
            rokidHardwareCompiled: true
        )

        let fieldNames = Set(Mirror(reflecting: result).children.compactMap(\.label))
        #expect(
            fieldNames == [
                "buildMode", "personalTeamMode", "shazamRecognitionAvailable", "shareExtensionAvailable",
                "appGroupAvailable", "rokidHardwareAvailable",
            ])
    }
}
