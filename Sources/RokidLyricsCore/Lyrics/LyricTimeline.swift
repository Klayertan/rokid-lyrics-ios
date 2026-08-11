import Foundation

public struct LyricTimelinePosition: Equatable, Sendable {
    public let previousLine: LyricLine?
    public let activeLine: LyricLine?
    public let nextLine: LyricLine?
    public let activeLineIndex: Int?
    public let playbackPosition: TimeInterval
    public let adjustedPosition: TimeInterval
    public let progress: Double?

    public init(
        previousLine: LyricLine?,
        activeLine: LyricLine?,
        nextLine: LyricLine?,
        activeLineIndex: Int?,
        playbackPosition: TimeInterval,
        adjustedPosition: TimeInterval,
        progress: Double?
    ) {
        self.previousLine = previousLine
        self.activeLine = activeLine
        self.nextLine = nextLine
        self.activeLineIndex = activeLineIndex
        self.playbackPosition = playbackPosition
        self.adjustedPosition = adjustedPosition
        self.progress = progress
    }
}

/// Performs binary-search lyric lookup over an immutable document.
///
/// A positive `syncOffsetSeconds` advances lyric selection; a negative value
/// delays it. The document's embedded LRC offset moves its timestamps, so it is
/// applied in the opposite direction during lookup.
public struct LyricTimeline: Sendable {
    public let document: LyricDocument
    public let trackDuration: TimeInterval?

    public init(document: LyricDocument, trackDuration: TimeInterval? = nil) {
        self.document = document
        self.trackDuration = trackDuration
    }

    public func position(
        at playbackPosition: TimeInterval,
        syncOffsetSeconds: TimeInterval = 0
    ) -> LyricTimelinePosition {
        let adjustedPosition = playbackPosition
            + syncOffsetSeconds
            - document.embeddedOffsetSeconds
        let insertionIndex = upperBound(for: adjustedPosition)
        let activeIndex = insertionIndex > 0 ? insertionIndex - 1 : nil

        let activeLine = activeIndex.map { document.lines[$0] }
        let previousLine = activeIndex.flatMap { index in
            index > 0 ? document.lines[index - 1] : nil
        }
        let nextIndex = activeIndex.map { $0 + 1 } ?? 0
        let nextLine = nextIndex < document.lines.count ? document.lines[nextIndex] : nil

        return LyricTimelinePosition(
            previousLine: previousLine,
            activeLine: activeLine,
            nextLine: nextLine,
            activeLineIndex: activeIndex,
            playbackPosition: playbackPosition,
            adjustedPosition: adjustedPosition,
            progress: progress(at: playbackPosition)
        )
    }

    public func line(at index: Int) -> LyricLine? {
        guard document.lines.indices.contains(index) else { return nil }
        return document.lines[index]
    }

    /// Returns the correction needed to make a line active at the supplied raw
    /// playback position.
    public func correctionToAlignLine(
        at index: Int,
        with playbackPosition: TimeInterval
    ) -> TimeInterval? {
        guard let line = line(at: index) else { return nil }
        return line.timestamp + document.embeddedOffsetSeconds - playbackPosition
    }

    private func upperBound(for timestamp: TimeInterval) -> Int {
        var lower = 0
        var upper = document.lines.count

        while lower < upper {
            let midpoint = lower + ((upper - lower) / 2)
            if document.lines[midpoint].timestamp <= timestamp {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }
        return lower
    }

    private func progress(at playbackPosition: TimeInterval) -> Double? {
        guard let duration = trackDuration, duration > 0 else { return nil }
        return min(max(playbackPosition / duration, 0), 1)
    }
}

