import Foundation

/// Snapshot of which optional capabilities this compiled build/signing
/// configuration actually has, so views can degrade cleanly instead of
/// assuming every full-development feature is present.
public struct AppCapabilities: Equatable, Sendable {
    public let buildMode: String
    public let personalTeamMode: Bool
    public let shazamRecognitionAvailable: Bool
    public let shareExtensionAvailable: Bool
    public let appGroupAvailable: Bool
    public let rokidHardwareAvailable: Bool

    public init(
        buildMode: String,
        personalTeamMode: Bool,
        shazamRecognitionAvailable: Bool,
        shareExtensionAvailable: Bool,
        appGroupAvailable: Bool,
        rokidHardwareAvailable: Bool
    ) {
        self.buildMode = buildMode
        self.personalTeamMode = personalTeamMode
        self.shazamRecognitionAvailable = shazamRecognitionAvailable
        self.shareExtensionAvailable = shareExtensionAvailable
        self.appGroupAvailable = appGroupAvailable
        self.rokidHardwareAvailable = rokidHardwareAvailable
    }
}

/// Resolves `AppCapabilities` from a target's expanded Info dictionary plus
/// the two facts that can only be known at compile time. Kept pure and
/// Foundation-only (no `Bundle.main`, no UIKit) so it is independently
/// testable; the app target supplies the real Info dictionary and compiled
/// flags.
public enum AppCapabilitiesResolver {
    public static let buildModeInfoDictionaryKey = "RokidLyricsBuildMode"
    public static let personalTeamModeInfoDictionaryKey = "RokidLyricsPersonalTeamMode"
    public static let shazamAvailableInfoDictionaryKey = "RokidLyricsShazamAvailable"
    public static let shareExtensionAvailableInfoDictionaryKey = "RokidLyricsShareExtensionAvailable"
    public static let appGroupAvailableInfoDictionaryKey = "RokidLyricsAppGroupAvailable"

    public static func resolve(
        infoDictionary: [String: Any]?,
        shazamCompiled: Bool,
        rokidHardwareCompiled: Bool
    ) -> AppCapabilities {
        AppCapabilities(
            buildMode: normalizedBuildMode(infoDictionary?[buildModeInfoDictionaryKey]),
            personalTeamMode: flag(infoDictionary?[personalTeamModeInfoDictionaryKey], default: false),
            shazamRecognitionAvailable:
                shazamCompiled && flag(infoDictionary?[shazamAvailableInfoDictionaryKey], default: true),
            shareExtensionAvailable: flag(infoDictionary?[shareExtensionAvailableInfoDictionaryKey], default: true),
            appGroupAvailable: flag(infoDictionary?[appGroupAvailableInfoDictionaryKey], default: true),
            rokidHardwareAvailable: rokidHardwareCompiled
        )
    }

    private static func normalizedBuildMode(_ value: Any?) -> String {
        guard let string = value as? String else { return "mock" }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed.contains("$(") ? "mock" : trimmed
    }

    private static func flag(_ value: Any?, default defaultValue: Bool) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        guard let stringValue = value as? String else { return defaultValue }
        switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "no", "false", "0": return false
        case "yes", "true", "1": return true
        default: return defaultValue
        }
    }
}
