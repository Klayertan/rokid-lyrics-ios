import Foundation
import Observation

enum RecognitionBehavior: String, CaseIterable, Identifiable {
    case identifyOnStart
    case manualSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identifyOnStart: return "Identify on Start"
        case .manualSearch: return "Manual search"
        }
    }
}

enum PlaceholderTextMode: String, CaseIterable, Identifiable {
    case off
    case planned

    var id: String { rawValue }
    var title: String { self == .off ? "Off" : "Planned (not implemented)" }
}

@MainActor
@Observable
final class AppSettings {
    var lineCount: Int { didSet { save() } }
    var fontScale: Double { didSet { save() } }
    var automaticReconnect: Bool { didSet { save() } }
    var defaultLyricOffset: Double { didSet { save() } }
    var mockMode: Bool { didSet { save() } }
    var showPreviousLine: Bool { didSet { save() } }
    var showNextLine: Bool { didSet { save() } }
    var verticalPosition: Double { didSet { save() } }
    var recognitionBehavior: RecognitionBehavior { didSet { save() } }
    var transliterationMode: PlaceholderTextMode { didSet { save() } }
    var translationMode: PlaceholderTextMode { didSet { save() } }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lineCount = max(1, min(3, defaults.object(forKey: Keys.lineCount) as? Int ?? 3))
        fontScale = max(0.75, min(1.6, defaults.object(forKey: Keys.fontScale) as? Double ?? 1))
        automaticReconnect = defaults.object(forKey: Keys.automaticReconnect) as? Bool ?? true
        defaultLyricOffset = max(-15, min(15, defaults.object(forKey: Keys.defaultLyricOffset) as? Double ?? 0))
        mockMode = defaults.object(forKey: Keys.mockMode) as? Bool ?? true
        showPreviousLine = defaults.object(forKey: Keys.showPreviousLine) as? Bool ?? true
        showNextLine = defaults.object(forKey: Keys.showNextLine) as? Bool ?? true
        verticalPosition = max(0, min(1, defaults.object(forKey: Keys.verticalPosition) as? Double ?? 0.5))
        recognitionBehavior =
            RecognitionBehavior(
                rawValue: defaults.string(forKey: Keys.recognitionBehavior) ?? ""
            ) ?? .identifyOnStart
        transliterationMode =
            PlaceholderTextMode(
                rawValue: defaults.string(forKey: Keys.transliterationMode) ?? ""
            ) ?? .off
        translationMode =
            PlaceholderTextMode(
                rawValue: defaults.string(forKey: Keys.translationMode) ?? ""
            ) ?? .off
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(lineCount, forKey: Keys.lineCount)
        defaults.set(fontScale, forKey: Keys.fontScale)
        defaults.set(automaticReconnect, forKey: Keys.automaticReconnect)
        defaults.set(defaultLyricOffset, forKey: Keys.defaultLyricOffset)
        defaults.set(mockMode, forKey: Keys.mockMode)
        defaults.set(showPreviousLine, forKey: Keys.showPreviousLine)
        defaults.set(showNextLine, forKey: Keys.showNextLine)
        defaults.set(verticalPosition, forKey: Keys.verticalPosition)
        defaults.set(recognitionBehavior.rawValue, forKey: Keys.recognitionBehavior)
        defaults.set(transliterationMode.rawValue, forKey: Keys.transliterationMode)
        defaults.set(translationMode.rawValue, forKey: Keys.translationMode)
    }

    private enum Keys {
        static let lineCount = "settings.lineCount"
        static let fontScale = "settings.fontScale"
        static let automaticReconnect = "settings.automaticReconnect"
        static let defaultLyricOffset = "settings.defaultLyricOffset"
        static let mockMode = "settings.mockMode"
        static let showPreviousLine = "settings.showPreviousLine"
        static let showNextLine = "settings.showNextLine"
        static let verticalPosition = "settings.verticalPosition"
        static let recognitionBehavior = "settings.recognitionBehavior"
        static let transliterationMode = "settings.transliterationMode"
        static let translationMode = "settings.translationMode"
    }
}
