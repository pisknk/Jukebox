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
import UIKit

// MARK: - Queue Entry

/// one slot in the play queue. each slot has its own id, so the same song can be queued twice
/// without confusing the queue list.
struct QueueEntry: Identifiable, Equatable {
    let id = UUID()
    let item: MPMediaItem

    static func == (lhs: QueueEntry, rhs: QueueEntry) -> Bool { lhs.id == rhs.id }
}

// MARK: - Playback Progress

/// the playback position lives in its own object so that only the views that show it
/// (progress bar, time labels, lyrics) redraw while music plays, not the whole app
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

final class MusicPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayerManager()

    let progress = PlaybackProgress()

    private var audioPlayer: AVAudioPlayer?
    private var crossfadePlayer: AVAudioPlayer?  // second player for crossfade
    private let audioSession = AVAudioSession.sharedInstance()

    // library
    @Published private(set) var songs: [MPMediaItem] = []
    /// bumps every time the library is (re)loaded, so views can refresh cached lists cheaply
    @Published private(set) var libraryVersion = 0
    private(set) var songsByID: [UInt64: MPMediaItem] = [:]
    @Published var hasPermission: Bool = false

    // now playing
    @Published private(set) var currentSong: MPMediaItem?
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentBitRate: Int? = nil

    var currentTime: TimeInterval { progress.currentTime }
    var duration: TimeInterval { progress.duration }

    // queue
    @Published private(set) var currentPlaylist: [QueueEntry] = []
    @Published private(set) var currentIndex: Int? = nil
    @Published private(set) var autoplayQueue: [QueueEntry] = []  // "Continue Playing"
    @Published var playbackContextTitle: String = "Unknown Context"
    private var originalPlaylist: [QueueEntry] = []  // order before shuffle

    // playback mode settings (persisted to UserDefaults)
    @Published var shuffleEnabled: Bool = false {
        didSet { UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled") }
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") }
    }
    @Published var autoplayEnabled: Bool = true {
        didSet { UserDefaults.standard.set(autoplayEnabled, forKey: "autoplayEnabled") }
    }

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
        // > 2000 kbps (approx 24/96) -> Hi-Res, > 500 kbps (FLAC/ALAC) -> Lossless,
        // > 250 kbps (AAC 256) -> High Quality, otherwise Standard
        if rate > 2000 { return .hiResLossless }
        if rate > 500 { return .lossless }
        if rate > 250 { return .highQuality }
        return .standard
    }

    // internal state
    private var progressTimer: Timer?
    private var crossfadeTimer: Timer?
    private var crossfadeTarget: CrossfadeTarget?
    private var isCrossfading: Bool { crossfadeTarget != nil }
    private var hasScrobbledCurrentSong = false
    private var currentSongStartedAt = Date()
    private var wasPlayingBeforeInterruption = false
    private var bitRateRequestID = 0
    private var libraryReloadWorkItem: DispatchWorkItem?
    private var isObservingLibrary = false

    private struct CrossfadeTarget {
        let entry: QueueEntry
        let fromAutoplay: Bool
    }

    // crossfade settings (read from UserDefaults, written by SettingsView)
    private var crossfadeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "crossfadeEnabled")
    }
    private var crossfadeDuration: Double {
        let duration = UserDefaults.standard.double(forKey: "crossfadeDuration")
        return duration > 0 ? duration : 6.0
    }

    private override init() {
        super.init()

        // only set the category here. the session is activated when playback starts,
        // so opening the app doesn't stop music playing in other apps.
        do {
            try audioSession.setCategory(.playback, mode: .default)
        } catch {
            print("failed to set audio session category: \(error.localizedDescription)")
        }

        setupRemoteCommandCenter()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: audioSession)
        center.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: audioSession)
        center.addObserver(self, selector: #selector(handleLibraryChange), name: .MPMediaLibraryDidChange, object: nil)

        loadPersistedSettings()
        checkPermission()
        startProgressTimer()
    }

    private func loadPersistedSettings() {
        shuffleEnabled = UserDefaults.standard.bool(forKey: "shuffleEnabled")
        if let savedRepeat = UserDefaults.standard.string(forKey: "repeatMode"),
           let mode = RepeatMode(rawValue: savedRepeat) {
            repeatMode = mode
        }
        // autoplay defaults to true if not set
        if UserDefaults.standard.object(forKey: "autoplayEnabled") != nil {
            autoplayEnabled = UserDefaults.standard.bool(forKey: "autoplayEnabled")
        }
    }

    deinit {
        progressTimer?.invalidate()
        crossfadeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Audio Session Events

    private func activateAudioSession() {
        do {
            try audioSession.setActive(true)
        } catch {
            print("failed to activate audio session: \(error.localizedDescription)")
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else { return }

        // headphones/bluetooth disconnected - pause playback
        DispatchQueue.main.async {
            if self.isPlaying { self.pause() }
        }
    }

    /// phone calls, siri, alarms, other apps taking over audio
    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0

        DispatchQueue.main.async {
            switch type {
            case .began:
                // the system has already paused our audio; keep our state in sync
                self.wasPlayingBeforeInterruption = self.isPlaying
                if self.isPlaying { self.pause() }
            case .ended:
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if self.wasPlayingBeforeInterruption && options.contains(.shouldResume) {
                    self.resume()
                }
                self.wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        }
    }

    // MARK: - Permission

    func checkPermission() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            hasPermission = true
            startObservingLibrary()
            loadSongs()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.hasPermission = status == .authorized
                    if status == .authorized {
                        self.startObservingLibrary()
                        self.loadSongs()
                    }
                }
            }
        default:
            hasPermission = false
        }
    }

    // MARK: - Library

    private func startObservingLibrary() {
        guard !isObservingLibrary else { return }
        isObservingLibrary = true
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
    }

    /// music synced or removed while the app is running
    @objc private func handleLibraryChange(_ notification: Notification) {
        DispatchQueue.main.async {
            // changes arrive in bursts during a sync; wait for them to settle
            self.libraryReloadWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.loadSongs() }
            self.libraryReloadWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    func loadSongs() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: false, forProperty: MPMediaItemPropertyIsCloudItem))
            // songs without a file (DRM-protected or not downloaded) can't be played by AVAudioPlayer
            let items = (query.items ?? []).filter { $0.assetURL != nil }

            var byID: [UInt64: MPMediaItem] = [:]
            byID.reserveCapacity(items.count)
            for item in items { byID[item.persistentID] = item }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.songs = items
                self.songsByID = byID
                self.libraryVersion += 1
                self.autoplayQueue.removeAll { byID[$0.item.persistentID] == nil }
                self.fillAutoplayQueue()
            }
        }
    }

    func song(withID id: UInt64) -> MPMediaItem? {
        songsByID[id]
    }

    // MARK: - Starting Playback

    /// plays `song` with `context` as the queue (album, playlist, the filtered list on screen...)
    func play(songs context: [MPMediaItem], startWith song: MPMediaItem, context title: String = "Tracks") {
        var entries = context.map { QueueEntry(item: $0) }
        var index = context.firstIndex(where: { $0.persistentID == song.persistentID })
        if index == nil {
            entries = [QueueEntry(item: song)]
            index = 0
        }
        guard let startIndex = index else { return }

        playbackContextTitle = "Playing from \(title)"
        originalPlaylist = entries
        if shuffleEnabled {
            currentPlaylist = QueueShuffler.shuffled(entries, keepingFirst: startIndex)
            startPlayback(at: 0)
        } else {
            currentPlaylist = entries
            startPlayback(at: startIndex)
        }
    }

    /// plays from the whole library
    func play(song: MPMediaItem) {
        play(songs: songs, startWith: song, context: "Tracks")
    }

    /// "Play" buttons: in order from the first song
    func playInOrder(songs list: [MPMediaItem], context title: String) {
        guard let first = list.first else { return }
        shuffleEnabled = false
        play(songs: list, startWith: first, context: title)
    }

    /// "Shuffle" buttons
    func playShuffled(songs list: [MPMediaItem], context title: String) {
        guard let start = list.randomElement() else { return }
        shuffleEnabled = true
        play(songs: list, startWith: start, context: title)
    }

    /// starts the song at `index` in the queue. songs that can't be played are skipped.
    private func startPlayback(at index: Int, skippedSoFar: Int = 0) {
        cancelCrossfade()
        guard currentPlaylist.indices.contains(index) else {
            finishQueue()
            return
        }

        // last chance to scrobble the song we're leaving
        scrobbleCurrentIfEligible()

        currentIndex = index
        let entry = currentPlaylist[index]
        if loadAndPlay(entry.item) { return }

        // this one can't be played (missing file, unsupported format) - try the next one
        let step = QueueNavigator.next(currentIndex: index, count: currentPlaylist.count,
                                       repeatMode: repeatMode == .one ? .off : repeatMode,
                                       autoplayAvailable: false)
        if case .index(let nextIndex) = step, skippedSoFar + 1 < currentPlaylist.count {
            startPlayback(at: nextIndex, skippedSoFar: skippedSoFar + 1)
        } else {
            // nothing playable: show the song we tried, stopped
            audioPlayer?.stop()
            audioPlayer = nil
            currentSong = entry.item
            currentArtwork = artworkImage(for: entry.item)
            progress.duration = 0
            finishQueue()
        }
    }

    /// returns false if the song couldn't be loaded
    private func loadAndPlay(_ song: MPMediaItem) -> Bool {
        guard let url = song.assetURL else {
            print("cannot play \(song.title ?? "song"): no asset url")
            return false
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            audioPlayer?.stop()
            audioPlayer = player

            activateAudioSession()
            player.volume = 1
            player.play()
            didStartSong(song, player: player)
            return true
        } catch {
            print("failed to play \(song.title ?? "song"): \(error.localizedDescription)")
            return false
        }
    }

    /// shared bookkeeping whenever a new song becomes the current one
    private func didStartSong(_ song: MPMediaItem, player: AVAudioPlayer) {
        currentSong = song
        currentArtwork = artworkImage(for: song)
        isPlaying = true
        progress.duration = player.duration
        progress.currentTime = player.currentTime
        hasScrobbledCurrentSong = false
        currentSongStartedAt = Date()

        loadBitRate(for: song)
        updateNowPlayingInfo()
        LastFMManager.shared.nowPlaying(song)
    }

    private func artworkImage(for song: MPMediaItem) -> UIImage? {
        song.artwork?.image(at: CGSize(width: 600, height: 600))
    }

    // MARK: - Transport Controls

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        // finishing a fade while paused would swap songs behind your back
        cancelCrossfade()
        audioPlayer?.pause()
        isPlaying = false
        if let player = audioPlayer { progress.currentTime = player.currentTime }
        updateNowPlayingInfo()
    }

    func resume() {
        guard let player = audioPlayer else {
            // nothing loaded yet (e.g. a song was queued while nothing was playing)
            if let index = currentIndex { startPlayback(at: index) }
            return
        }
        activateAudioSession()
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func next() {
        cancelCrossfade()
        advance()
    }

    func previous() {
        cancelCrossfade()
        let elapsed = audioPlayer?.currentTime ?? progress.currentTime
        switch QueueNavigator.previous(currentIndex: currentIndex, count: currentPlaylist.count, elapsed: elapsed, repeatMode: repeatMode) {
        case .restart:
            seek(to: 0)
        case .index(let index):
            startPlayback(at: index)
        }
    }

    func seek(to time: TimeInterval) {
        cancelCrossfade()
        guard let player = audioPlayer else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        progress.currentTime = clamped
        updateNowPlayingInfo()
    }

    /// moves on to whatever comes after the current song
    private func advance() {
        let step = QueueNavigator.next(currentIndex: currentIndex, count: currentPlaylist.count,
                                       repeatMode: repeatMode, autoplayAvailable: autoplayEnabled && !songs.isEmpty)
        switch step {
        case .index(let index):
            startPlayback(at: index)
        case .autoplay:
            playNextAutoplaySong()
        case .stop:
            finishQueue()
        }
    }

    /// nothing left to play: stop at the start of the last song
    private func finishQueue() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        progress.currentTime = 0
        updateNowPlayingInfo()
    }

    // MARK: - Shuffle / Repeat / Autoplay

    func toggleShuffle() {
        setShuffle(!shuffleEnabled)
    }

    func setShuffle(_ enabled: Bool) {
        guard enabled != shuffleEnabled else { return }
        shuffleEnabled = enabled
        guard let index = currentIndex, currentPlaylist.indices.contains(index) else { return }

        if enabled {
            originalPlaylist = currentPlaylist
            currentPlaylist = QueueShuffler.shuffled(currentPlaylist, keepingFirst: index)
            currentIndex = 0
        } else {
            let restored = QueueShuffler.unshuffled(current: currentPlaylist, original: originalPlaylist, playing: currentPlaylist[index])
            currentPlaylist = restored.items
            currentIndex = restored.index
        }
    }

    func cycleRepeatMode() {
        repeatMode.cycle()
    }

    func toggleAutoplay() {
        autoplayEnabled.toggle()
        if autoplayEnabled {
            fillAutoplayQueue()
        }
    }

    private func playNextAutoplaySong() {
        if autoplayQueue.isEmpty { fillAutoplayQueue() }
        guard !autoplayQueue.isEmpty else {
            finishQueue()
            return
        }
        let entry = autoplayQueue.removeFirst()
        currentPlaylist.append(entry)
        fillAutoplayQueue()
        startPlayback(at: currentPlaylist.count - 1)
    }

    func fillAutoplayQueue() {
        guard !songs.isEmpty else { return }

        let targetSize = 20
        let needed = targetSize - autoplayQueue.count
        guard needed > 0 else { return }

        // prefer songs that aren't already queued
        let existingIDs = Set(currentPlaylist.map { $0.item.persistentID } + autoplayQueue.map { $0.item.persistentID })
        var candidates = songs.filter { !existingIDs.contains($0.persistentID) }
        if candidates.isEmpty {
            candidates = songs  // small library: allow repeats
        }
        candidates.shuffle()
        autoplayQueue.append(contentsOf: candidates.prefix(needed).map { QueueEntry(item: $0) })
    }

    // MARK: - Queue Management

    /// songs after the current one
    var upcomingEntries: [QueueEntry] {
        guard let index = currentIndex, index + 1 < currentPlaylist.count else { return [] }
        return Array(currentPlaylist[(index + 1)...])
    }

    /// offsets are positions in `upcomingEntries`
    func moveUpcoming(from source: IndexSet, to destination: Int) {
        guard let index = currentIndex else { return }
        let head = Array(currentPlaylist[...index])
        currentPlaylist = head + ArrayEditing.moving(upcomingEntries, fromOffsets: source, toOffset: destination)
    }

    /// offsets are positions in `upcomingEntries`
    func removeUpcoming(at offsets: IndexSet) {
        guard let index = currentIndex else { return }
        let head = Array(currentPlaylist[...index])
        currentPlaylist = head + ArrayEditing.removing(upcomingEntries, atOffsets: offsets)
    }

    /// "Add to Queue": plays right after the current song
    func addToQueue(song: MPMediaItem) {
        let entry = QueueEntry(item: song)
        if let index = currentIndex, currentPlaylist.indices.contains(index) {
            currentPlaylist.insert(entry, at: index + 1)
        } else {
            // nothing playing yet: make it the current song, ready to play
            currentPlaylist = [entry]
            originalPlaylist = [entry]
            currentIndex = 0
            currentSong = song
            currentArtwork = artworkImage(for: song)
            playbackContextTitle = "Playing from Queue"
        }
    }

    /// offset is a position in `upcomingEntries`
    func playUpcoming(at offset: Int) {
        guard let index = currentIndex else { return }
        startPlayback(at: index + 1 + offset)
    }

    /// tapping a song in "Continue Playing"
    func playFromAutoplayQueue(at offset: Int) {
        guard autoplayQueue.indices.contains(offset) else { return }
        let entry = autoplayQueue[offset]
        autoplayQueue.removeFirst(offset + 1)
        let insertAt = (currentIndex ?? -1) + 1
        currentPlaylist.insert(entry, at: min(insertAt, currentPlaylist.count))
        fillAutoplayQueue()
        startPlayback(at: min(insertAt, currentPlaylist.count - 1))
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.handleSongFinished(player)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("decode error: \(error?.localizedDescription ?? "unknown")")
        DispatchQueue.main.async {
            self.handleSongFinished(player)
        }
    }

    private func handleSongFinished(_ player: AVAudioPlayer) {
        // ignore players we've already swapped out
        guard player === audioPlayer else { return }

        // the old song ran out slightly before the fade timer finished
        if isCrossfading {
            completeCrossfade()
            return
        }

        // played to the end
        scrobbleCurrentIfEligible(playedToEnd: true)

        if repeatMode == .one {
            player.currentTime = 0
            player.play()
            if let song = currentSong {
                didStartSong(song, player: player)
            }
            return
        }

        let sleepTimer = SleepTimerManager.shared
        if sleepTimer.isActive && sleepTimer.timerType == .afterOneSong {
            finishQueue()
            sleepTimer.stopTimer()
            return
        }

        advance()
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so it keeps running while the user scrolls
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func tick() {
        guard isPlaying, let player = audioPlayer else { return }
        progress.currentTime = player.currentTime
        scrobbleCurrentIfEligible()
        startCrossfadeIfNeeded(player)
    }

    // MARK: - Scrobbling

    private func scrobbleCurrentIfEligible(playedToEnd: Bool = false) {
        guard !hasScrobbledCurrentSong, let song = currentSong, let player = audioPlayer else { return }
        let played = playedToEnd ? player.duration : player.currentTime
        if ScrobbleRule.shouldScrobble(played: played, duration: player.duration, threshold: LastFMManager.shared.scrobblePercent) {
            LastFMManager.shared.scrobble(song, startedAt: currentSongStartedAt)
            hasScrobbledCurrentSong = true
        }
    }

    // MARK: - Crossfade

    private func startCrossfadeIfNeeded(_ player: AVAudioPlayer) {
        guard crossfadeEnabled, !isCrossfading, repeatMode != .one else { return }

        // let the song end normally so "stop after this song" can trigger
        let sleepTimer = SleepTimerManager.shared
        if sleepTimer.isActive && sleepTimer.timerType == .afterOneSong { return }

        // never fade for more than half of a short song
        let fadeLength = min(crossfadeDuration, player.duration / 2)
        let remaining = player.duration - player.currentTime
        guard remaining <= fadeLength, remaining > 0.5 else { return }

        startCrossfade(over: remaining)
    }

    private func startCrossfade(over fadeLength: TimeInterval) {
        let step = QueueNavigator.next(currentIndex: currentIndex, count: currentPlaylist.count,
                                       repeatMode: repeatMode, autoplayAvailable: autoplayEnabled && !songs.isEmpty)
        let target: CrossfadeTarget
        switch step {
        case .index(let index):
            target = CrossfadeTarget(entry: currentPlaylist[index], fromAutoplay: false)
        case .autoplay:
            if autoplayQueue.isEmpty { fillAutoplayQueue() }
            guard let first = autoplayQueue.first else { return }
            target = CrossfadeTarget(entry: first, fromAutoplay: true)
        case .stop:
            return
        }

        // if the next song can't be loaded, let this one end normally and advance() will skip it
        guard let url = target.entry.item.assetURL,
              let incoming = try? AVAudioPlayer(contentsOf: url) else { return }

        incoming.volume = 0
        incoming.prepareToPlay()
        incoming.play()
        crossfadePlayer = incoming
        crossfadeTarget = target

        let start = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, self.isCrossfading else {
                timer.invalidate()
                return
            }
            let fraction = min(1, Date().timeIntervalSince(start) / fadeLength)
            self.audioPlayer?.volume = Float(1 - fraction)
            self.crossfadePlayer?.volume = Float(fraction)
            if fraction >= 1 {
                timer.invalidate()
                self.completeCrossfade()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        crossfadeTimer = timer
    }

    private func completeCrossfade() {
        guard let target = crossfadeTarget, let incoming = crossfadePlayer else { return }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil

        // the outgoing song played to the end
        scrobbleCurrentIfEligible(playedToEnd: true)

        audioPlayer?.stop()
        incoming.delegate = self
        incoming.volume = 1
        audioPlayer = incoming
        crossfadePlayer = nil
        crossfadeTarget = nil

        // put the new song in its place in the queue
        if target.fromAutoplay {
            autoplayQueue.removeAll { $0.id == target.entry.id }
            currentPlaylist.append(target.entry)
            currentIndex = currentPlaylist.count - 1
            fillAutoplayQueue()
        } else if let index = currentPlaylist.firstIndex(of: target.entry) {
            currentIndex = index
        } else {
            // the song was removed from the queue while fading in; keep it right after the old one
            let insertAt = min((currentIndex ?? -1) + 1, currentPlaylist.count)
            currentPlaylist.insert(target.entry, at: insertAt)
            currentIndex = insertAt
        }

        didStartSong(target.entry.item, player: incoming)
    }

    private func cancelCrossfade() {
        guard isCrossfading || crossfadePlayer != nil else { return }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadePlayer?.stop()
        crossfadePlayer = nil
        crossfadeTarget = nil
        audioPlayer?.volume = 1.0
    }

    // MARK: - Bit Rate

    private func loadBitRate(for song: MPMediaItem) {
        currentBitRate = nil
        bitRateRequestID += 1
        let requestID = bitRateRequestID
        guard let url = song.assetURL else { return }

        Task {
            var kbps: Int? = nil
            let asset = AVURLAsset(url: url)
            if let track = (try? await asset.loadTracks(withMediaType: .audio))?.first,
               let rate = try? await track.load(.estimatedDataRate) {
                kbps = Int(rate / 1000)
            }
            DispatchQueue.main.async { [weak self] in
                // ignore results for a song we've already skipped past
                guard let self = self, self.bitRateRequestID == requestID else { return }
                self.currentBitRate = kbps
            }
        }
    }

    // MARK: - Remote Command Center (Control Center / Lock Screen / headphones / CarPlay)

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }

        // wired headphone button and some bluetooth remotes
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.next()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.currentSong != nil else { return .noActionableNowPlayingItem }
            self.previous()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    /// call on song change, play, pause and seek. between those, iOS advances the
    /// lock screen position by itself using the playback rate.
    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: song.title ?? "Unknown Title",
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPMediaItemPropertyAlbumTitle: song.albumTitle ?? "",
            MPMediaItemPropertyPlaybackDuration: audioPlayer?.duration ?? progress.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audioPlayer?.currentTime ?? progress.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let artwork = song.artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
