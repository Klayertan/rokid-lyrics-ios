import Foundation
import RokidLyricsCore

public actor UserDefaultsSyncCorrectionStore: SyncCorrectionStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private var corrections: [String: TimeInterval]

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "perTrackSyncCorrections"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        corrections = defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, pair in
            if let value = pair.value as? NSNumber {
                result[pair.key] = value.doubleValue
            }
        } ?? [:]
    }

    public func correction(forTrackID trackID: String) -> TimeInterval? {
        corrections[trackID]
    }

    public func saveCorrection(_ correction: TimeInterval, forTrackID trackID: String) {
        corrections[trackID] = correction
        persist()
    }

    public func removeCorrection(forTrackID trackID: String) {
        corrections.removeValue(forKey: trackID)
        persist()
    }

    private func persist() {
        defaults.set(corrections, forKey: storageKey)
    }
}
