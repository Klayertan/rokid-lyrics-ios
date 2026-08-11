import Foundation

public protocol SyncCorrectionStore: Sendable {
    func correction(forTrackID trackID: String) async -> TimeInterval?
    func saveCorrection(_ correction: TimeInterval, forTrackID trackID: String) async
    func removeCorrection(forTrackID trackID: String) async
}

public actor InMemorySyncCorrectionStore: SyncCorrectionStore {
    private var corrections: [String: TimeInterval]

    public init(corrections: [String: TimeInterval] = [:]) {
        self.corrections = corrections
    }

    public func correction(forTrackID trackID: String) async -> TimeInterval? {
        corrections[trackID]
    }

    public func saveCorrection(
        _ correction: TimeInterval,
        forTrackID trackID: String
    ) async {
        corrections[trackID] = correction
    }

    public func removeCorrection(forTrackID trackID: String) async {
        corrections.removeValue(forKey: trackID)
    }

    public func allCorrections() async -> [String: TimeInterval] {
        corrections
    }
}
