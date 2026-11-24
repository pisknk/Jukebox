//
//  SleepTimerManager.swift
//  Jukebox
//
//  Manages sleep timer functionality to stop music after specified duration or time.
//

import Foundation
import Combine

enum SleepTimerType: String, CaseIterable, Codable {
    case off = "Off"
    case afterOneSong = "After 1 Song"
    case fifteenMinutes = "15 Minutes"
    case thirtyMinutes = "30 Minutes"
    case oneHour = "1 Hour"
    case atSpecificTime = "At Specific Time"

    var displayName: String {
        return self.rawValue
    }

    var icon: String {
        switch self {
        case .off: return "moon.zzz"
        case .afterOneSong: return "music.note"
        case .fifteenMinutes, .thirtyMinutes, .oneHour: return "timer"
        case .atSpecificTime: return "clock"
        }
    }
}

final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var timerType: SleepTimerType = .off
    @Published private(set) var fireDate: Date?
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private init() {}

    /// start timer based on type. `specificTime` is only used for `.atSpecificTime`
    /// (only its hour and minute matter).
    func startTimer(type: SleepTimerType, specificTime: Date? = nil) {
        stopTimer()
        let now = Date()

        let date: Date?
        switch type {
        case .off:
            return
        case .afterOneSong:
            date = nil
        case .fifteenMinutes:
            date = now.addingTimeInterval(15 * 60)
        case .thirtyMinutes:
            date = now.addingTimeInterval(30 * 60)
        case .oneHour:
            date = now.addingTimeInterval(60 * 60)
        case .atSpecificTime:
            guard let time = specificTime else { return }
            // worked out once, so the deadline stays put and the timer actually fires
            date = SleepTimerMath.fireDate(forTimeOfDay: time, after: now)
        }

        timerType = type
        isActive = true
        fireDate = date

        if let date = date {
            remainingTime = date.timeIntervalSince(now)
            // counts down from a fixed deadline, so it stays accurate even if ticks are delayed
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func tick() {
        guard let fireDate = fireDate else { return }
        remainingTime = max(0, fireDate.timeIntervalSinceNow)
        if remainingTime <= 0 {
            triggerSleep()
        }
    }

    func triggerSleep() {
        let manager = MusicPlayerManager.shared
        if manager.isPlaying {
            manager.pause()
        }
        stopTimer()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerType = .off
        isActive = false
        fireDate = nil
        remainingTime = 0
    }

    // formatted remaining time string
    var formattedRemainingTime: String {
        if timerType == .afterOneSong {
            return "After this song"
        }

        let total = Int(remainingTime.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // short description for queue view
    var shortDescription: String {
        switch timerType {
        case .off:
            return ""
        case .afterOneSong:
            return "Stops after this song"
        case .fifteenMinutes, .thirtyMinutes, .oneHour:
            return "Stops in \(formattedRemainingTime)"
        case .atSpecificTime:
            guard let fireDate = fireDate else { return "" }
            return "Stops at \(Self.timeFormatter.string(from: fireDate))"
        }
    }
}
