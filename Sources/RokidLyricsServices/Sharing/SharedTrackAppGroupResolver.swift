import Foundation

/// Resolves the App Group injected by Xcode build settings into each target's
/// Info.plist. The pure dictionary overload keeps configuration behavior
/// deterministic and independently testable.
public enum SharedTrackAppGroupResolver {
    public static let infoDictionaryKey = "RokidLyricsAppGroupIdentifier"
    public static let defaultIdentifier = "group.com.rokidlyrics.shared"

    public static func resolve(
        infoDictionary: [String: Any]?,
        fallbackIdentifier: String = defaultIdentifier
    ) -> String {
        let fallback = normalized(fallbackIdentifier) ?? defaultIdentifier
        guard
            let configuredValue = infoDictionary?[infoDictionaryKey] as? String,
            let configuredIdentifier = normalized(configuredValue)
        else {
            return fallback
        }
        return configuredIdentifier
    }

    private static func normalized(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            candidate.count > "group.".count,
            candidate.hasPrefix("group."),
            !candidate.contains("$("),
            !candidate.contains("${"),
            candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return nil
        }
        return candidate
    }
}
