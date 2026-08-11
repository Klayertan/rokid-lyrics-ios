import Foundation
import RokidLyricsCore

public protocol LyricsCache: Sendable {
    func candidates(for key: String) async -> [LyricsCandidate]?
    func store(_ candidates: [LyricsCandidate], for key: String) async
}

public actor MemoryLyricsCache: LyricsCache {
    private var values: [String: [LyricsCandidate]] = [:]
    private let maximumEntryCount: Int

    public init(maximumEntryCount: Int = 100) {
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    public func candidates(for key: String) -> [LyricsCandidate]? {
        values[key]
    }

    public func store(_ candidates: [LyricsCandidate], for key: String) {
        if values.count >= maximumEntryCount, values[key] == nil, let firstKey = values.keys.first {
            values.removeValue(forKey: firstKey)
        }
        values[key] = candidates
    }
}

public actor DiskLyricsCache: LyricsCache {
    private struct Entry: Codable {
        let storedAt: Date
        let candidates: [LyricsCandidate]
    }

    private let directoryURL: URL
    private let maximumEntryCount: Int
    private let lifetime: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directoryURL: URL,
        maximumEntryCount: Int = 100,
        lifetime: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.directoryURL = directoryURL
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.lifetime = max(0, lifetime)
    }

    public func candidates(for key: String) -> [LyricsCandidate]? {
        let fileURL = fileURL(for: key)
        guard
            let data = try? Data(contentsOf: fileURL),
            let entry = try? decoder.decode(Entry.self, from: data)
        else {
            return nil
        }

        guard Date().timeIntervalSince(entry.storedAt) <= lifetime else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return entry.candidates
    }

    public func store(_ candidates: [LyricsCandidate], for key: String) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let entry = Entry(storedAt: Date(), candidates: candidates)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key), options: .atomic)
            pruneIfNeeded()
        } catch {
            // Cache failures must never make runtime lyric lookup fail.
        }
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(Self.fnv1aHex(key), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func pruneIfNeeded() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ),
            files.count > maximumEntryCount
        else { return }

        let ordered = files.sorted { lhs, rhs in
            let left = try? lhs.resourceValues(forKeys: keys).contentModificationDate
            let right = try? rhs.resourceValues(forKeys: keys).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        for file in ordered.prefix(files.count - maximumEntryCount) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func fnv1aHex(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
