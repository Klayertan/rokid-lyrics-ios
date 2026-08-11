import Foundation

public protocol MonotonicTimeSource: Sendable {
    var now: TimeInterval { get }
}

public struct SystemMonotonicTimeSource: MonotonicTimeSource {
    public init() {}

    public var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

public enum LyricPlaybackClockState: String, Codable, Equatable, Sendable {
    case stopped
    case running
    case paused
}

/// A small clock anchored exclusively to monotonic time. Wall-clock changes do
/// not affect lyric position.
public struct LyricPlaybackClock: Equatable, Sendable {
    public private(set) var state: LyricPlaybackClockState = .stopped
    private var anchorPosition: TimeInterval = 0
    private var anchorMonotonicTime: TimeInterval = 0

    public init() {}

    public var isRunning: Bool { state == .running }

    public func position(at monotonicTime: TimeInterval) -> TimeInterval {
        guard state == .running else { return max(anchorPosition, 0) }
        let elapsed = max(monotonicTime - anchorMonotonicTime, 0)
        return max(anchorPosition + elapsed, 0)
    }

    public mutating func start(
        at playbackPosition: TimeInterval = 0,
        monotonicTime: TimeInterval
    ) {
        anchorPosition = max(playbackPosition, 0)
        anchorMonotonicTime = monotonicTime
        state = .running
    }

    public mutating func pause(at monotonicTime: TimeInterval) {
        guard state == .running else { return }
        anchorPosition = position(at: monotonicTime)
        anchorMonotonicTime = monotonicTime
        state = .paused
    }

    public mutating func resume(at monotonicTime: TimeInterval) {
        guard state == .paused || state == .stopped else { return }
        anchorMonotonicTime = monotonicTime
        state = .running
    }

    public mutating func seek(
        to playbackPosition: TimeInterval,
        at monotonicTime: TimeInterval
    ) {
        anchorPosition = max(playbackPosition, 0)
        anchorMonotonicTime = monotonicTime
    }

    public mutating func stop() {
        anchorPosition = 0
        anchorMonotonicTime = 0
        state = .stopped
    }
}

