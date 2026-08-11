import Foundation

public actor SharedTrackInbox {
    public static let defaultAppGroupIdentifier = "group.com.rokidlyrics.shared"
    private static let storageKey = "pendingSharedTrackDraft"

    private let defaults: UserDefaults?

    public init(appGroupIdentifier: String = SharedTrackInbox.defaultAppGroupIdentifier) {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    public func save(_ draft: SharedTrackDraft) throws {
        let data = try JSONEncoder().encode(draft)
        defaults?.set(data, forKey: Self.storageKey)
    }

    public func peek() -> SharedTrackDraft? {
        guard
            let data = defaults?.data(forKey: Self.storageKey),
            let draft = try? JSONDecoder().decode(SharedTrackDraft.self, from: data)
        else { return nil }
        return draft
    }

    public func take() -> SharedTrackDraft? {
        let draft = peek()
        defaults?.removeObject(forKey: Self.storageKey)
        return draft
    }
}
