//
//  main.swift
//  LogicTests
//
//  Tests for the pure logic in Jukebox/Jukebox/Logic. Compiled together with those files
//  and run on the macOS CI runner:
//    swiftc -o logic-tests Jukebox/Jukebox/Logic/*.swift Tests/LogicTests/main.swift && ./logic-tests
//

import Foundation

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    check(actual == expected, "\(message) — expected \(expected), got \(actual)", line: line)
}

struct Item: Identifiable, Equatable { let id: Int }

// MARK: - Queue navigation

checkEqual(QueueNavigator.next(currentIndex: 0, count: 3, repeatMode: .off, autoplayAvailable: true), .index(1), "next goes forward")
checkEqual(QueueNavigator.next(currentIndex: 2, count: 3, repeatMode: .off, autoplayAvailable: false), .stop, "end of queue with nothing else stops")
checkEqual(QueueNavigator.next(currentIndex: 2, count: 3, repeatMode: .off, autoplayAvailable: true), .autoplay, "end of queue uses autoplay")
checkEqual(QueueNavigator.next(currentIndex: 2, count: 3, repeatMode: .all, autoplayAvailable: true), .index(0), "repeat all wins over autoplay")
checkEqual(QueueNavigator.next(currentIndex: 2, count: 3, repeatMode: .one, autoplayAvailable: false), .stop, "manual next with repeat one at the end stops")
checkEqual(QueueNavigator.next(currentIndex: nil, count: 3, repeatMode: .all, autoplayAvailable: true), .stop, "no current index stops")
checkEqual(QueueNavigator.next(currentIndex: 0, count: 0, repeatMode: .all, autoplayAvailable: true), .stop, "empty queue stops")

checkEqual(QueueNavigator.previous(currentIndex: 2, count: 3, elapsed: 10, repeatMode: .off), .restart, "previous after 3s restarts")
checkEqual(QueueNavigator.previous(currentIndex: 2, count: 3, elapsed: 1, repeatMode: .off), .index(1), "previous early goes back")
checkEqual(QueueNavigator.previous(currentIndex: 0, count: 3, elapsed: 1, repeatMode: .off), .restart, "previous on first song restarts")
checkEqual(QueueNavigator.previous(currentIndex: 0, count: 3, elapsed: 1, repeatMode: .all), .index(2), "previous on first song wraps with repeat all")

// MARK: - Shuffle

do {
    let items = (0..<50).map(Item.init)
    let shuffled = QueueShuffler.shuffled(items, keepingFirst: 7)
    checkEqual(shuffled.first, Item(id: 7), "shuffle keeps the chosen song first")
    checkEqual(Set(shuffled.map(\.id)), Set(items.map(\.id)), "shuffle keeps every song")
    checkEqual(shuffled.count, items.count, "shuffle doesn't duplicate songs")
}

do {
    let original = [1, 2, 3, 4, 5].map(Item.init)
    // shuffled queue, playing 3; 4 was removed; 9 was added with "play next" after 3
    let current = [3, 9, 5, 1, 2].map(Item.init)
    let (items, index) = QueueShuffler.unshuffled(current: current, original: original, playing: Item(id: 3))
    checkEqual(items.map(\.id), [1, 2, 3, 9, 5], "unshuffle restores order, drops removed, keeps added after current")
    checkEqual(index, 2, "unshuffle points at the playing song")
}

do {
    let original = [1, 2].map(Item.init)
    let current = [2, 1, 8].map(Item.init) // 8 came from autoplay and is playing
    let (items, index) = QueueShuffler.unshuffled(current: current, original: original, playing: Item(id: 8))
    checkEqual(items.map(\.id), [1, 2, 8], "unshuffle when the playing song was added later")
    checkEqual(index, 2, "index of an added playing song")
}

// MARK: - Array editing

checkEqual(ArrayEditing.moving([0, 1, 2, 3], fromOffsets: IndexSet([0]), toOffset: 3), [1, 2, 0, 3], "move down")
checkEqual(ArrayEditing.moving([0, 1, 2, 3], fromOffsets: IndexSet([3]), toOffset: 0), [3, 0, 1, 2], "move up")
checkEqual(ArrayEditing.moving([0, 1, 2, 3], fromOffsets: IndexSet([1]), toOffset: 4), [0, 2, 3, 1], "move to end")
checkEqual(ArrayEditing.moving([0, 1, 2, 3], fromOffsets: IndexSet([0, 2]), toOffset: 4), [1, 3, 0, 2], "move several")
checkEqual(ArrayEditing.removing([0, 1, 2, 3, 4], atOffsets: IndexSet([1, 3])), [0, 2, 4], "remove several at once")

// MARK: - Playlist ordering (songs missing from the device must not shift edits)

do {
    // 20 isn't on this device
    let stored: [UInt64] = [10, 20, 30, 40]
    let available: Set<UInt64> = [10, 30, 40]
    let visible = PlaylistOrdering.visibleIndices(storedIDs: stored, isAvailable: { available.contains($0) })
    checkEqual(visible, [0, 2, 3], "visible rows map to stored positions")

    // delete the second visible row (30)
    let storedOffsets = PlaylistOrdering.storedOffsets(forVisible: IndexSet([1]), visibleIndices: visible)
    checkEqual(ArrayEditing.removing(stored, atOffsets: storedOffsets), [10, 20, 40], "delete removes the song you tapped, not its neighbour")

    // drag the last visible row (40) to the top
    let moved = PlaylistOrdering.applyingVisibleMove(storedIDs: stored, visibleIndices: visible, from: IndexSet([2]), to: 0)
    checkEqual(moved, [40, 20, 10, 30], "move reorders visible songs and leaves the missing one in place")
}

// MARK: - Scrobble rules

check(!ScrobbleRule.shouldScrobble(played: 25, duration: 29, threshold: 0.5), "songs of 30s or less never scrobble")
check(ScrobbleRule.shouldScrobble(played: 100, duration: 200, threshold: 0.5), "scrobbles at threshold")
check(!ScrobbleRule.shouldScrobble(played: 99, duration: 200, threshold: 0.5), "not before threshold")
check(ScrobbleRule.shouldScrobble(played: 240, duration: 1200, threshold: 0.9), "scrobbles after 4 minutes regardless of threshold")

// MARK: - Sleep timer

do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    func date(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: h, minute: m, second: s))!
    }
    let now = date(22, 0)
    checkEqual(SleepTimerMath.fireDate(forTimeOfDay: date(23, 30), after: now, calendar: calendar), date(23, 30), "later today")
    checkEqual(SleepTimerMath.fireDate(forTimeOfDay: date(7, 0), after: now, calendar: calendar), date(7, 0, day: 2), "earlier time means tomorrow")
    // the old bug: once the target passed, it kept moving to tomorrow and never fired.
    // the fire date must stay fixed, so remaining time reaches zero.
    let fire = SleepTimerMath.fireDate(forTimeOfDay: date(22, 1), after: now, calendar: calendar)
    check(fire.timeIntervalSince(date(22, 1, 1)) <= 0, "remaining time reaches zero after the target passes")
}

// MARK: - LRC parsing

do {
    let lrc = "[ar:Someone]\r\n[00:01.50]First\r\n[00:03.123]Second\r\n[00:05]Third"
    let lines = LRCParser.parse(lrc)
    checkEqual(lines.map(\.text), ["First", "Second", "Third"], "basic lines, metadata ignored, CRLF handled")
    checkEqual(lines.map(\.time), [1.5, 3.123, 5], "2-digit, 3-digit and no fractions")
}

do {
    let lines = LRCParser.parse("[00:10.00][00:30.00]Chorus\n[00:20.00]Verse")
    checkEqual(lines.map(\.text), ["Chorus", "Verse", "Chorus"], "repeated timestamps expand")
    check(!lines.contains { $0.text.contains("[") }, "no raw timestamps left in text")
}

do {
    let lines = LRCParser.parse("[00:00.50]\n[00:01.00]Hello\n[00:10.00]\n[00:11.00]\n[00:20.00]World")
    checkEqual(lines.map(\.text), ["Hello", "", "World"], "leading break dropped, repeated breaks collapsed")
}

do {
    let lines = LRCParser.parse("[offset:+500]\n[00:02.00]Early")
    checkEqual(lines.first?.time, 1.5, "offset shifts lines earlier")
}

do {
    let lines = LRCParser.parse("[00:01.00]A\n[00:02.00]B\n[00:03.00]C")
    checkEqual(LRCParser.lineIndex(at: 0.5, in: lines), nil, "nothing highlighted before the first line")
    checkEqual(LRCParser.lineIndex(at: 1.0, in: lines), 0, "line starts exactly on time")
    checkEqual(LRCParser.lineIndex(at: 2.5, in: lines), 1, "middle")
    checkEqual(LRCParser.lineIndex(at: 99, in: lines), 2, "after the last line")
    checkEqual(LRCParser.lineIndex(at: 1, in: []), nil, "empty lyrics")
}

// MARK: - Encoding & signing

checkEqual(FormEncoding.encode("Simon & Garfunkel"), "Simon%20%26%20Garfunkel", "ampersand and spaces are encoded")
checkEqual(FormEncoding.encode("a+b=c"), "a%2Bb%3Dc", "plus and equals are encoded")
checkEqual(FormEncoding.encode("Beyoncé"), "Beyonc%C3%A9", "non-ASCII letters are encoded")
checkEqual(FormEncoding.query(["b": "2", "a": "x y"]), "a=x%20y&b=2", "query is sorted and encoded")

do {
    // expected value computed independently: md5("api_keyKmethodMsecret")
    let sig = LastFMSignature.sign(["method": "M", "api_key": "K", "format": "json"], secret: "secret")
    checkEqual(sig, "678785a0df9bdc90b7761041731ef836", "signature matches md5 of sorted params + secret")
    let again = LastFMSignature.sign(["api_key": "K", "method": "M"], secret: "secret")
    checkEqual(sig, again, "format is excluded and key order doesn't matter")
}

do {
    let batch = PendingScrobble.batchParameters([
        PendingScrobble(artist: "A", track: "T1", album: "X", duration: 200, timestamp: 100),
        PendingScrobble(artist: "B", track: "T2", album: nil, duration: nil, timestamp: 200),
    ])
    checkEqual(batch["artist[0]"], "A", "batch artist 0")
    checkEqual(batch["track[1]"], "T2", "batch track 1")
    checkEqual(batch["timestamp[1]"], "200", "batch keeps the start time")
    check(batch["album[1]"] == nil, "missing album omitted")
}

checkEqual(MusicBrainzQuery.artistQuery("AC/DC"), "artist:\"AC/DC\"", "phrase query")
checkEqual(MusicBrainzQuery.artistQuery("The \"Band\""), "artist:\"The \\\"Band\\\"\"", "quotes escaped")

do {
    let name = ArtistImageNaming.fileName(for: "AC/DC")
    check(!name.contains("/"), "file names never contain slashes")
    checkEqual(name, ArtistImageNaming.fileName(for: "  ac/dc "), "same artist, same file")
    check(name.hasSuffix(".jpg"), "jpg extension")
}

// MARK: - Repeat mode

do {
    var mode = RepeatMode.off
    mode.cycle(); checkEqual(mode, .all, "off -> all")
    mode.cycle(); checkEqual(mode, .one, "all -> one")
    mode.cycle(); checkEqual(mode, .off, "one -> off")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
