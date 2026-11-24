//
//  PlaybackLogic.swift
//  Jukebox
//
//  Pure playback rules (queue navigation, shuffle, scrobbling, sleep timer maths).
//  Foundation only, so it can be unit tested outside the app (see Tests/LogicTests).
//

import Foundation

// MARK: - Repeat Mode
enum RepeatMode: String, CaseIterable {
    case off, all, one

    var icon: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    mutating func cycle() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }
}

// MARK: - Queue Navigation

/// what should happen after the current song
enum QueueStep: Equatable {
    case index(Int)   // play this position in the queue
    case autoplay     // play the next song from the autoplay ("Continue Playing") queue
    case stop         // nothing left to play
}

/// what the previous button should do
enum PreviousStep: Equatable {
    case restart      // go back to the start of the current song
    case index(Int)   // play this position in the queue
}

enum QueueNavigator {
    /// the song that follows the current one. used by the next button, by natural song
    /// endings and by crossfade, so all three always agree.
    /// repeat all wins over autoplay: if you asked to loop the queue, it loops.
    static func next(currentIndex: Int?, count: Int, repeatMode: RepeatMode, autoplayAvailable: Bool) -> QueueStep {
        guard count > 0, let index = currentIndex else { return .stop }
        if index + 1 < count { return .index(index + 1) }
        if repeatMode == .all { return .index(0) }
        if autoplayAvailable { return .autoplay }
        return .stop
    }

    /// more than 3 seconds in restarts the song, otherwise goes back one
    static func previous(currentIndex: Int?, count: Int, elapsed: TimeInterval, repeatMode: RepeatMode) -> PreviousStep {
        guard count > 0, let index = currentIndex, elapsed <= 3 else { return .restart }
        if index > 0 { return .index(index - 1) }
        if repeatMode == .all { return .index(count - 1) }
        return .restart
    }
}

// MARK: - Shuffle

enum QueueShuffler {
    /// moves the item at `index` to the front and shuffles everything else after it
    static func shuffled<T>(_ items: [T], keepingFirst index: Int) -> [T] {
        guard items.indices.contains(index) else { return items.shuffled() }
        var rest = items
        let first = rest.remove(at: index)
        rest.shuffle()
        return [first] + rest
    }

    /// turns shuffle off: restores the original order, drops anything that was removed from the
    /// queue in the meantime, and keeps anything added since (play next / autoplay) right after
    /// the song that's playing so it still plays next.
    static func unshuffled<T: Identifiable>(current: [T], original: [T], playing: T) -> (items: [T], index: Int) {
        let currentIDs = Set(current.map(\.id))
        let originalIDs = Set(original.map(\.id))
        var restored = original.filter { currentIDs.contains($0.id) }
        let added = current.filter { !originalIDs.contains($0.id) }

        if let position = restored.firstIndex(where: { $0.id == playing.id }) {
            restored.insert(contentsOf: added, at: position + 1)
        } else {
            // the playing song itself was added after shuffling started
            restored.append(contentsOf: added)
        }
        let index = restored.firstIndex(where: { $0.id == playing.id }) ?? 0
        return (restored, index)
    }
}

// MARK: - Array helpers

enum ArrayEditing {
    /// same behaviour as SwiftUI's `move(fromOffsets:toOffset:)`, without needing SwiftUI
    static func moving<T>(_ array: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        let valid = source.filter { array.indices.contains($0) }
        guard !valid.isEmpty else { return array }
        let moving = valid.map { array[$0] }
        var result = array
        for index in valid.sorted(by: >) { result.remove(at: index) }
        let insertAt = min(result.count, max(0, destination - valid.filter { $0 < destination }.count))
        result.insert(contentsOf: moving, at: insertAt)
        return result
    }

    static func removing<T>(_ array: [T], atOffsets offsets: IndexSet) -> [T] {
        var result = array
        for index in offsets.sorted(by: >) where result.indices.contains(index) {
            result.remove(at: index)
        }
        return result
    }
}

// MARK: - Scrobbling

enum ScrobbleRule {
    /// last.fm rules: the track must be longer than 30 seconds, and must have been played for
    /// the chosen share of its length or for 4 minutes, whichever comes first
    static func shouldScrobble(played: TimeInterval, duration: TimeInterval, threshold: Double) -> Bool {
        guard duration > 30 else { return false }
        return played >= duration * threshold || played >= 240
    }
}

// MARK: - Sleep Timer

enum SleepTimerMath {
    /// the next moment the clock shows the hour and minute of `timeOfDay`, strictly after `now`
    static func fireDate(forTimeOfDay timeOfDay: Date, after now: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: timeOfDay)
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(24 * 60 * 60)
    }
}

// MARK: - Playlists

enum PlaylistOrdering {
    /// the rows a playlist shows: songs that are on this device, with their position in the saved list
    static func visibleIndices(storedIDs: [UInt64], isAvailable: (UInt64) -> Bool) -> [Int] {
        storedIDs.indices.filter { isAvailable(storedIDs[$0]) }
    }

    /// applies a drag-to-reorder of the visible rows to the saved list. songs that aren't on this
    /// device right now stay exactly where they were.
    static func applyingVisibleMove(storedIDs: [UInt64], visibleIndices: [Int], from source: IndexSet, to destination: Int) -> [UInt64] {
        let visibleIDs = visibleIndices.map { storedIDs[$0] }
        let reordered = ArrayEditing.moving(visibleIDs, fromOffsets: source, toOffset: destination)
        var result = storedIDs
        for (slot, id) in zip(visibleIndices, reordered) {
            result[slot] = id
        }
        return result
    }

    /// turns positions on screen into positions in the saved list
    static func storedOffsets(forVisible offsets: IndexSet, visibleIndices: [Int]) -> IndexSet {
        IndexSet(offsets.compactMap { visibleIndices.indices.contains($0) ? visibleIndices[$0] : nil })
    }
}
