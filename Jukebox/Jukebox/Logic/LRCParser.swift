//
//  LRCParser.swift
//  Jukebox
//
//  Parses synced (.lrc) lyrics. Foundation only, so it can be unit tested.
//

import Foundation

// MARK: - lyric line model
struct LyricLine: Identifiable, Codable, Equatable {
    let id: UUID
    let time: TimeInterval  // time in seconds
    let text: String        // empty means an instrumental break

    init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }

    var isInstrumental: Bool { text.isEmpty }

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.time == rhs.time && lhs.text == rhs.text
    }
}

enum LRCParser {
    private static let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let offsetTag = try! NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\s*\]"#, options: .caseInsensitive)

    /// supports `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, several timestamps on one line
    /// (repeated choruses), `[offset:±ms]`, and windows line endings.
    /// empty lines become instrumental breaks; leading and repeated breaks are dropped.
    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(time: TimeInterval, order: Int, text: String)] = []
        var offset: TimeInterval = 0
        var order = 0

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let ns = line as NSString
            if line.isEmpty { continue }

            if let match = offsetTag.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               let ms = Double(ns.substring(with: match.range(at: 1))) {
                // positive offset = lyrics should appear earlier
                offset = ms / 1000
                continue
            }

            // read every timestamp at the start of the line
            var times: [TimeInterval] = []
            var location = 0
            while location < ns.length,
                  let match = timestamp.firstMatch(in: line, options: .anchored, range: NSRange(location: location, length: ns.length - location)) {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = ns.substring(with: match.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                times.append(minutes * 60 + seconds + fraction)
                location = match.range.location + match.range.length
                // allow spaces between stacked timestamps
                while location < ns.length, ns.character(at: location) == 32 { location += 1 }
            }
            guard !times.isEmpty else { continue } // metadata tags like [ar:...] or plain text

            let text = ns.substring(from: location).trimmingCharacters(in: .whitespaces)
            for time in times {
                entries.append((max(0, time - offset), order, text))
                order += 1
            }
        }

        entries.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }

        var lines: [LyricLine] = []
        for entry in entries {
            if entry.text.isEmpty {
                // skip a break before the first line, and collapse back-to-back breaks
                guard let last = lines.last, !last.isInstrumental else { continue }
            }
            lines.append(LyricLine(time: entry.time, text: entry.text))
        }
        return lines
    }

    /// the last line that has started at `time`, or nil before the first line
    static func lineIndex(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count - 1
        var result: Int? = nil
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
