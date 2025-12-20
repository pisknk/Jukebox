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

class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()
    
    @Published var timerType: SleepTimerType = .off
    @Published var targetTime: Date = Date()
    @Published var remainingTime: TimeInterval = 0
    @Published var isActive: Bool = false
    @Published var songsRemaining: Int = 0
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // start timer based on type
    func startTimer(type: SleepTimerType, specificTime: Date? = nil) {
        stopTimer()
        timerType = type
        isActive = type != .off
        
        switch type {
        case .off:
            return
        case .afterOneSong:
            songsRemaining = 1
        case .fifteenMinutes:
            remainingTime = 15 * 60
            startCountdownTimer()
        case .thirtyMinutes:
            remainingTime = 30 * 60
            startCountdownTimer()
        case .oneHour:
            remainingTime = 60 * 60
            startCountdownTimer()
        case .atSpecificTime:
            if let time = specificTime {
                targetTime = time
                calculateRemainingTimeToTarget()
                startCountdownTimer()
            }
        }
    }
    
    private func calculateRemainingTimeToTarget() {
        let now = Date()
        var target = targetTime
        
        // if target is before now, assume it's tomorrow
        if target <= now {
            target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target
        }
        
        remainingTime = target.timeIntervalSince(now)
    }
    
    private func startCountdownTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.timerType == .atSpecificTime {
                self.calculateRemainingTimeToTarget()
            } else {
                self.remainingTime -= 1
            }
            
            if self.remainingTime <= 0 {
                self.triggerSleep()
            }
        }
    }
    
    // called when song finishes playing
    func onSongFinished() {
        guard isActive && timerType == .afterOneSong else { return }
        
        songsRemaining -= 1
        if songsRemaining <= 0 {
            triggerSleep()
        }
    }
    
    func triggerSleep() {
        // stop playback if playing
        let manager = MusicPlayerManager.shared
        if manager.isPlaying {
            manager.togglePlayPause()
        }
        stopTimer()
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerType = .off
        isActive = false
        remainingTime = 0
        songsRemaining = 0
    }
    
    // formatted remaining time string
    var formattedRemainingTime: String {
        if timerType == .afterOneSong {
            return "After this song"
        }
        
        let hours = Int(remainingTime) / 3600
        let minutes = (Int(remainingTime) % 3600) / 60
        let seconds = Int(remainingTime) % 60
        
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
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Stops at \(formatter.string(from: targetTime))"
        }
    }
}
