//
//  MusicPlayerManager.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import Foundation
import MediaPlayer
import AVFoundation
import Combine

// MARK: - Repeat Mode
enum RepeatMode: String, CaseIterable {
    case off, all, one
    
    var icon: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
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

class MusicPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayerManager()
    
    private var audioPlayer: AVAudioPlayer?
    private var crossfadePlayer: AVAudioPlayer?  // second player for crossfade
    private var audioSession = AVAudioSession.sharedInstance()
    
    @Published var songs: [MPMediaItem] = []
    
    var albums: [MPMediaItemCollection] {
        MPMediaQuery.albums().collections ?? []
    }
    
    @Published var currentSong: MPMediaItem?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var hasPermission: Bool = false
    @Published var currentBitRate: Int? = nil
    
    private var timer: Timer?
    private var crossfadeTimer: Timer?  // timer for fade animation
    private var isCrossfading: Bool = false
    
    @Published var currentPlaylist: [MPMediaItem] = []
    @Published private(set) var currentIndex: Int? = nil
    
    // playback mode settings
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var autoplayEnabled: Bool = true
    
    // original playlist order (before shuffle)
    private var originalPlaylist: [MPMediaItem] = []
    
    // playback context title (e.g., "Playing from Album Name")
    @Published var playbackContextTitle: String = "Unknown Context"
    
    // autoplay queue (upcoming random songs)
    @Published var autoplayQueue: [MPMediaItem] = []
    
    // Audio Quality Logic
    enum AudioQuality {
        case standard
        case highQuality
        case lossless
        case hiResLossless
        
        var badgeText: String {
            switch self {
            case .standard: return "Standard"
            case .highQuality: return "High Quality"
            case .lossless: return "Lossless"
            case .hiResLossless: return "Hi-Res Lossless"
            }
        }
        
        var iconName: String {
            switch self {
            case .standard: return "waveform"
            case .highQuality: return "waveform"
            case .lossless: return "waveform.badge.plus"
            case .hiResLossless: return "waveform.badge.magnifyingglass"
            }
        }
    }
    
    var audioQuality: AudioQuality? {
        guard let rate = currentBitRate else { return nil }
        // thresholds:
        // > 2000 kbps (approx 24/96) -> Hi-Res
        // > 500 kbps (FLAC/ALAC typical) -> Lossless
        // > 250 kbps (AAC 256) -> High Quality
        // < 250 -> Standard
        
        if rate > 2000 { return .hiResLossless }
        if rate > 500 { return .lossless }
        if rate > 250 { return .highQuality }
        return .standard
    }
    
    // Last.fm state
    private var hasScrobbledCurrentSong = false
    
    // crossfade settings (read from UserDefaults)
    private var crossfadeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "crossfadeEnabled")
    }
    private var crossfadeDuration: Double {
        let duration = UserDefaults.standard.double(forKey: "crossfadeDuration")
        return duration > 0 ? duration : 6.0
    }

    
    private override init() {
        super.init()
        
        // configure audio session
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("failed to set up audio session: \(error.localizedDescription)")
        }
        
        // setup remote command center for control center and lock screen
        setupRemoteCommandCenter()
        
        // request media library permission
        checkPermission()
        
        // start timer for progress updates
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
        crossfadeTimer?.invalidate()
    }
    
    // MARK: - Permission
    
    func checkPermission() {
        let status = MPMediaLibrary.authorizationStatus()
        print("media library authorization status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            hasPermission = true
            loadSongs()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    print("permission request result: \(status.rawValue)")
                    self?.hasPermission = status == .authorized
                    if status == .authorized {
                        self?.loadSongs()
                    }
                }
            }
        default:
            hasPermission = false
            print("media library permission denied or restricted")
        }
    }
    
    // MARK: - Load Songs
    
    func loadSongs() {
        let query = MPMediaQuery.songs()
        songs = query.items ?? []
        print("loaded \(songs.count) songs from media library")
        
        // debug: print first few songs
        for (index, song) in songs.prefix(5).enumerated() {
            print("song \(index): \(song.title ?? "unknown") - assetURL: \(song.assetURL != nil ? "available" : "nil")")
        }
        
        // initialize autoplay queue
        fillAutoplayQueue()
    }
    
    // MARK: - Shuffle Control
    
    func toggleShuffle() {
        shuffleEnabled.toggle()
        
        guard !currentPlaylist.isEmpty, let currentIndex = currentIndex else { return }
        
        if shuffleEnabled {
            // save original order and shuffle
            originalPlaylist = currentPlaylist
            let currentSongItem = currentPlaylist[currentIndex]
            
            // shuffle remaining songs (keep current song at position 0)
            var remaining = currentPlaylist
            remaining.remove(at: currentIndex)
            remaining.shuffle()
            
            currentPlaylist = [currentSongItem] + remaining
            self.currentIndex = 0
        } else {
            // restore original order
            if !originalPlaylist.isEmpty, let song = currentSong {
                currentPlaylist = originalPlaylist
                // find current song in original playlist
                if let newIndex = currentPlaylist.firstIndex(where: { $0.persistentID == song.persistentID }) {
                    self.currentIndex = newIndex
                }
            }
        }
    }
    
    // MARK: - Repeat Control
    
    func cycleRepeatMode() {
        repeatMode.cycle()
    }
    
    // MARK: - Autoplay Control
    
    func toggleAutoplay() {
        autoplayEnabled.toggle()
        if autoplayEnabled {
            fillAutoplayQueue()
        }
    }
    
    // MARK: - Queue Management
    
    func moveQueueItem(from source: IndexSet, to destination: Int) {
        guard let currentIndex = currentIndex else { return }
        
        // adjust indices relative to the queue (which starts after current song)
        let adjustedSource = IndexSet(source.map { $0 + currentIndex + 1 })
        let adjustedDestination = destination + currentIndex + 1
        
        currentPlaylist.move(fromOffsets: adjustedSource, toOffset: adjustedDestination)
    }
    
    func removeFromQueue(at index: Int) {
        guard index > 0, index < currentPlaylist.count else { return }
        currentPlaylist.remove(at: index)
    }
    
    func addToQueue(song: MPMediaItem) {
        // add song to play next (after current song)
        if let currentIndex = currentIndex {
            let insertIndex = currentIndex + 1
            currentPlaylist.insert(song, at: insertIndex)
        } else {
            // no current song, just add to end
            currentPlaylist.append(song)
        }
    }
    
    func playFromQueueAtIndex(_ index: Int) {
        guard index >= 0, index < currentPlaylist.count else { return }
        
        // set current index to this song and play it
        currentIndex = index
        let song = currentPlaylist[index]
        
        // setup and play
        hasScrobbledCurrentSong = false
        currentSong = song
        
        guard let assetURL = song.assetURL else { return }
        
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: assetURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = crossfadeEnabled ? 1.0 : 1.0
            audioPlayer?.play()
            
            isPlaying = true
            currentTime = 0
            duration = audioPlayer?.duration ?? 0
            
            LastFMManager.shared.scrobble(song)
            updateNowPlayingInfo()
            startTimer()
        } catch {
            print("error playing song: \(error)")
        }
    }
    
    // MARK: - Playback Controls
    
    func play(song: MPMediaItem) {
        // play from the full song list, starting at this song (default context)
        play(songs: self.songs, startWith: song, context: "Tracks")
    }
    
    func play(songs context: [MPMediaItem], startWith song: MPMediaItem, context title: String = "Tracks") {
        guard let index = context.firstIndex(where: { $0.persistentID == song.persistentID }) else {
            // fallback if not found in context
            playSingle(song: song)
            return
        }
        
        // update context title
        self.playbackContextTitle = "Playing from \(title)"
        
        if shuffleEnabled {
            // create shuffled playlist with selected song first
            var remaining = context
            remaining.remove(at: index)
            remaining.shuffle()
            
            // set playlist
            self.currentPlaylist = [song] + remaining
            self.originalPlaylist = context
            self.currentIndex = 0
        } else {
            // set playlist
            self.currentPlaylist = context
            self.originalPlaylist = context
            self.currentIndex = index
        }
        
        playSingle(song: song)
    }
    
    private func playSingle(song: MPMediaItem) {
        // check if we should scrobble previous song (if skipped significantly through)
        if !hasScrobbledCurrentSong, let oldSong = currentSong, let player = audioPlayer {
            // rule: > threshold % or > 4 mins
            let threshold = LastFMManager.shared.scrobblePercent
            if player.currentTime > (player.duration * threshold) || player.currentTime > 240 {
                LastFMManager.shared.scrobble(oldSong)
            }
        }
        hasScrobbledCurrentSong = false
        
        // stop current playback
        audioPlayer?.stop()
        
        // get the asset URL
        guard let assetURL = song.assetURL else {
            print("cannot play song: assetURL is nil")
            return
        }
        
        do {
            // create and configure audio player
            audioPlayer = try AVAudioPlayer(contentsOf: assetURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            currentSong = song
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            
            // extract bit rate from asset
            extractBitRate(from: assetURL)
            
            // update now playing info for control center / lock screen
            updateNowPlayingInfo()
            
            // update last.fm now playing
            LastFMManager.shared.nowPlaying(song)
        } catch {
            print("failed to play song: \(error.localizedDescription)")
        }
    }
    
    private func extractBitRate(from url: URL) {
        let asset = AVAsset(url: url)
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                if let track = tracks.first {
                    let bitRate = try await track.load(.estimatedDataRate)
                    await MainActor.run {
                        // convert bits per second to kbps
                        self.currentBitRate = Int(bitRate / 1000)
                    }
                }
            } catch {
                print("failed to extract bit rate: \(error)")
                await MainActor.run {
                    self.currentBitRate = nil
                }
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    func next() {
        guard !currentPlaylist.isEmpty, let index = currentIndex else { return }
        
        // check if we're at the end
        if index >= currentPlaylist.count - 1 {
            // at the end of playlist
            if autoplayEnabled {
                // pick a random song from library
                playRandomSong()
            } else if repeatMode == .all {
                // repeat all: go back to beginning
                currentIndex = 0
                playSingle(song: currentPlaylist[0])
            }
            // if repeat is off and autoplay is off, do nothing
        } else {
            // normal next
            currentIndex = index + 1
            playSingle(song: currentPlaylist[currentIndex!])
        }
    }
    
    func previous() {
        guard !currentPlaylist.isEmpty, let index = currentIndex else { return }
        
        // if more than 3 seconds into song, restart it
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        
        // otherwise go to previous
        if index > 0 {
            currentIndex = index - 1
            playSingle(song: currentPlaylist[currentIndex!])
        } else if repeatMode == .all {
            // wrap to end
            currentIndex = currentPlaylist.count - 1
            playSingle(song: currentPlaylist[currentIndex!])
        }
    }
    
    func playRandomSong() {
        guard !songs.isEmpty else { return }
        
        // ensure queue has items
        if autoplayQueue.isEmpty {
            fillAutoplayQueue()
        }
        
        if !autoplayQueue.isEmpty {
            let nextSong = autoplayQueue.removeFirst()
            
            // add to end of playlist and play it
            currentPlaylist.append(nextSong)
            currentIndex = currentPlaylist.count - 1
            playSingle(song: nextSong)
            
            // replenish queue
            fillAutoplayQueue()
        }
    }
    
    func fillAutoplayQueue() {
        guard !songs.isEmpty else { return }
        
        // target size for autoplay queue
        let targetSize = 20
        let needed = targetSize - autoplayQueue.count
        guard needed > 0 else { return }
        
        var availableSongs = songs
        
        // exclude existing playlist and queue
        let existingIDs = Set(currentPlaylist.map { $0.persistentID } + autoplayQueue.map { $0.persistentID })
        availableSongs.removeAll { existingIDs.contains($0.persistentID) }
        
        // if we ran out of unique songs, just use all songs (fallback)
        if availableSongs.isEmpty {
            availableSongs = songs
        }
        
        // shuffle and pick needed amount
        if !availableSongs.isEmpty {
            var candidates = availableSongs
            candidates.shuffle()
            let count = min(needed, candidates.count)
            let newSongs = Array(candidates.prefix(count))
            autoplayQueue.append(contentsOf: newSongs)
        }
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        
        // if crossfade just completed, don't process again (crossfade already transitioned)
        // this can happen when old player fully finishes after crossfade swapped it out
        if player !== audioPlayer {
            return
        }
        
        // scrobble if we haven't yet (song finished = 100% played, always meets threshold)
        if !hasScrobbledCurrentSong, let song = currentSong {
            LastFMManager.shared.scrobble(song)
            hasScrobbledCurrentSong = true
        }
        
        // check repeat mode
        if repeatMode == .one {
            // repeat the same song
            hasScrobbledCurrentSong = false // reset for next loop
            seek(to: 0)
            audioPlayer?.play()
            return
        }
        
        // check sleep timer - stop if "after 1 song" is active
        let sleepTimer = SleepTimerManager.shared
        if sleepTimer.isActive && sleepTimer.timerType == .afterOneSong {
            sleepTimer.triggerSleep()
            return
        }
        
        // otherwise go to next
        next()
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
            self.updateNowPlayingProgress()
            
            // check if we should scrobble (threshold reached or 4 minutes played)
            if !self.hasScrobbledCurrentSong, let song = self.currentSong {
                let threshold = LastFMManager.shared.scrobblePercent
                let thresholdTime = player.duration * threshold
                
                if player.currentTime >= thresholdTime || player.currentTime >= 240 {
                    LastFMManager.shared.scrobble(song)
                    self.hasScrobbledCurrentSong = true
                    print("scrobbled at \(Int(threshold * 100))% threshold")
                }
            }
            
            // check for crossfade trigger
            if self.crossfadeEnabled && !self.isCrossfading && self.repeatMode != .one {
                // don't crossfade if sleep timer is set to stop after this song
                let sleepTimer = SleepTimerManager.shared
                if sleepTimer.isActive && sleepTimer.timerType == .afterOneSong {
                    // let song finish normally so sleep timer can trigger
                } else {
                    let timeRemaining = player.duration - player.currentTime
                    if timeRemaining <= self.crossfadeDuration && timeRemaining > 0.5 {
                        self.startCrossfade()
                    }
                }
            }
        }
    }
    
    // MARK: - Crossfade
    
    private func startCrossfade() {
        guard !isCrossfading else { return }
        
        // get next song
        guard let nextSong = getNextSongForCrossfade() else { return }
        guard let assetURL = nextSong.assetURL else { return }
        
        isCrossfading = true
        
        // prepare the crossfade player with next song
        do {
            crossfadePlayer = try AVAudioPlayer(contentsOf: assetURL)
            crossfadePlayer?.volume = 0  // start silent
            crossfadePlayer?.prepareToPlay()
            crossfadePlayer?.play()
            
            // fade volumes over crossfade duration
            let fadeSteps = 20
            let fadeInterval = crossfadeDuration / Double(fadeSteps)
            var step = 0
            
            crossfadeTimer?.invalidate()
            crossfadeTimer = Timer.scheduledTimer(withTimeInterval: fadeInterval, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                
                step += 1
                let progress = Double(step) / Double(fadeSteps)
                
                // fade out current, fade in next
                self.audioPlayer?.volume = Float(1.0 - progress)
                self.crossfadePlayer?.volume = Float(progress)
                
                if step >= fadeSteps {
                    timer.invalidate()
                    self.completeCrossfade(to: nextSong)
                }
            }
        } catch {
            print("crossfade failed: \(error.localizedDescription)")
            isCrossfading = false
        }
    }
    
    private func getNextSongForCrossfade() -> MPMediaItem? {
        // similar logic to next() but without playing
        if let currentIndex = currentIndex {
            let nextIndex = currentIndex + 1
            if nextIndex < currentPlaylist.count {
                return currentPlaylist[nextIndex]
            } else if repeatMode == .all {
                return currentPlaylist.first
            } else if autoplayEnabled && !autoplayQueue.isEmpty {
                return autoplayQueue.first
            }
        }
        return nil
    }
    
    private func completeCrossfade(to song: MPMediaItem) {
        // stop old player
        audioPlayer?.stop()
        
        // swap players
        audioPlayer = crossfadePlayer
        audioPlayer?.delegate = self
        audioPlayer?.volume = 1.0
        crossfadePlayer = nil
        
        // update state
        currentSong = song
        duration = audioPlayer?.duration ?? 0
        currentTime = 0
        hasScrobbledCurrentSong = false
        
        // update index
        if let idx = currentPlaylist.firstIndex(where: { $0.persistentID == song.persistentID }) {
            currentIndex = idx
        } else if !autoplayQueue.isEmpty {
            autoplayQueue.removeFirst()
        }
        
        // update bit rate and now playing info
        if let url = song.assetURL {
            extractBitRate(from: url)
        }
        updateNowPlayingInfo()
        LastFMManager.shared.nowPlaying(song)
        
        isCrossfading = false
    }
    
    // MARK: - Remote Command Center (Control Center / Lock Screen)
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // play command
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // pause command
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // next command
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        // previous command
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        // seek command
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: song.title ?? "Unknown Title",
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPMediaItemPropertyAlbumTitle: song.albumTitle ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        // add artwork if available
        if let artwork = song.artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlayingProgress() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
