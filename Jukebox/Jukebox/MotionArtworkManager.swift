//
//  MotionArtworkManager.swift
//  Jukebox
//
//  Animated album covers (Apple Music motion covers) in Native Glass, iOS 26+:
//  - on the lock screen, through iOS 26's MPMediaItemAnimatedArtwork
//  - full-bleed at the top of Now Playing
//
//  Finding and downloading the covers is ported from pisknk/deezit (see the
//  MotionArtwork folder). Off in Amity 1.0, in Low Power Mode, and with the
//  "Animated Album Covers" switch in Settings.
//

import Foundation
import MediaPlayer
import Combine
import UIKit

final class MotionArtworkManager: ObservableObject {
    static let shared = MotionArtworkManager()

    /// UserDefaults key for the Settings switch (on unless turned off)
    static let settingKey = "animatedAlbumCovers"

    /// the 3:4 motion cover video for the song that's playing, once it's ready
    @Published private(set) var currentVideo: URL?

    private enum Entry {
        case ready(fileName: String)        // a video in Caches/Jukebox/motion
        case missing(since: Date)           // nothing found (retried after 30 min)
        case noAlbumCover(albumID: String)  // Apple Music has the album, without a motion cover
    }

    /// keyed by album ("artist|album") or song ("artist|album|title")
    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private var currentAlbumKey: String?
    private var currentTrackKey: String?
    /// one MPMediaItemAnimatedArtwork per video file, reused across now-playing updates
    private var lockScreenArtwork: [String: Any] = [:]

    private let readyStorageKey = "motionCoverFiles"
    private let retryInterval: TimeInterval = 30 * 60
    private var lastSong: MPMediaItem?

    private init() {
        // covers found in earlier launches (album/song key -> file name)
        if let saved = UserDefaults.standard.dictionary(forKey: readyStorageKey) as? [String: String] {
            for (key, file) in saved { entries[key] = .ready(fileName: file) }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil
        )
    }

    // MARK: - Switches

    var isEnabled: Bool {
        guard AppDesign.isNativeGlass else { return false }
        let defaults = UserDefaults.standard
        let switchOn = defaults.object(forKey: Self.settingKey) == nil || defaults.bool(forKey: Self.settingKey)
        return switchOn && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// the Settings switch was flipped
    func settingChanged() {
        songDidChange(lastSong)
        MusicPlayerManager.shared.refreshNowPlayingInfo()
    }

    @objc private func powerStateChanged() {
        DispatchQueue.main.async { self.settingChanged() }
    }

    // MARK: - Current song

    /// call on the main thread whenever a new song starts
    func songDidChange(_ song: MPMediaItem?) {
        lastSong = song
        guard isEnabled,
              let song = song,
              let artist = song.artist ?? song.albumArtist, !artist.isEmpty,
              let title = song.title, !title.isEmpty else {
            currentAlbumKey = nil
            currentTrackKey = nil
            setCurrentVideo(nil)
            return
        }

        let album = song.albumTitle
        let albumKey = "\(artist)|\(album?.isEmpty == false ? album! : title)".lowercased()
        let trackKey = "\(albumKey)|\(title.lowercased())"
        currentAlbumKey = albumKey
        currentTrackKey = trackKey
        setCurrentVideo(videoForCurrentSong())

        let duration = song.playbackDuration
        switch entries[albumKey] {
        case .noAlbumCover(let albumID):
            // the album has no motion cover: try this song's other releases
            if needsLookup(trackKey) {
                resolveTrack(trackKey, title: title, artist: artist, excludeAlbumID: albumID, duration: duration)
            }
        default:
            if needsLookup(albumKey) {
                resolveAlbum(albumKey, trackKey: trackKey, title: title, artist: artist, album: album, duration: duration)
            }
        }
    }

    /// the animated artwork to add to the now-playing info, if this song has one
    func lockScreenEntry(still: MPMediaItemArtwork?) -> (key: String, value: Any)? {
        guard isEnabled, let video = currentVideo, let key = JBAnimatedArtworkKey3x4() else { return nil }
        let name = video.lastPathComponent
        if let cached = lockScreenArtwork[name] {
            return (key, cached)
        }
        guard let artwork = JBMakeAnimatedArtwork("jukebox-\(name)", video, still) else { return nil }
        lockScreenArtwork[name] = artwork
        return (key, artwork)
    }

    // MARK: - Lookup

    private func videoForCurrentSong() -> URL? {
        guard let albumKey = currentAlbumKey else { return nil }
        if let url = readyFile(albumKey) { return url }
        if let trackKey = currentTrackKey, let url = readyFile(trackKey) { return url }
        return nil
    }

    /// the cached video for a key, if it's still on disk (iOS can purge Caches)
    private func readyFile(_ key: String) -> URL? {
        guard case .ready(let fileName) = entries[key] else { return nil }
        let url = JBMotionCacheDirectory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        entries.removeValue(forKey: key)
        saveReady()
        return nil
    }

    private func needsLookup(_ key: String) -> Bool {
        guard !inFlight.contains(key) else { return false }
        switch entries[key] {
        case nil: return true
        case .missing(let since): return Date().timeIntervalSince(since) > retryInterval
        case .ready: return readyFile(key) == nil
        case .noAlbumCover: return false
        }
    }

    private func resolveAlbum(_ albumKey: String, trackKey: String, title: String, artist: String,
                              album: String?, duration: TimeInterval) {
        inFlight.insert(albumKey)
        JBAppleMotionCover(title, artist, album, duration) { [weak self] albumID, tall, square, note in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let albumID = albumID else {
                    self.giveUp(albumKey, note: note)
                    return
                }
                if tall != nil || square != nil {
                    self.prepare(albumKey, albumID: albumID, tall: tall, square: square)
                    return
                }
                // Apple Music has the album but no motion cover for it
                self.inFlight.remove(albumKey)
                self.entries[albumKey] = .noAlbumCover(albumID: albumID)
                if self.currentAlbumKey == albumKey, self.needsLookup(trackKey) {
                    self.resolveTrack(trackKey, title: title, artist: artist, excludeAlbumID: albumID, duration: duration)
                }
            }
        }
    }

    private func resolveTrack(_ trackKey: String, title: String, artist: String,
                              excludeAlbumID: String?, duration: TimeInterval) {
        inFlight.insert(trackKey)
        JBAppleMotionCoverFromOtherReleases(title, artist, excludeAlbumID, duration) { [weak self] albumID, tall, square, note in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let albumID = albumID, tall != nil || square != nil else {
                    self.giveUp(trackKey, note: note)
                    return
                }
                self.prepare(trackKey, albumID: albumID, tall: tall, square: square)
            }
        }
    }

    /// downloads the 3:4 clip, or the square one cropped to 3:4
    private func prepare(_ key: String, albumID: String, tall: URL?, square: URL?) {
        let finish: (URL?, String) -> Void = { [weak self] file, note in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let file = file else {
                    self.giveUp(key, note: note)
                    return
                }
                self.inFlight.remove(key)
                self.entries[key] = .ready(fileName: file.lastPathComponent)
                self.saveReady()
                // show it now if this song is still playing
                if key == self.currentAlbumKey || key == self.currentTrackKey {
                    self.setCurrentVideo(file)
                    MusicPlayerManager.shared.refreshNowPlayingInfo()
                }
            }
        }
        if let tall = tall {
            JBMotionFile(tall, "\(albumID)-3x4", finish)
        } else if let square = square {
            JBMotionFileSquareTo3x4(square, "\(albumID)-sq3x4", finish)
        } else {
            giveUp(key, note: "no motion cover")
        }
    }

    private func giveUp(_ key: String, note: String) {
        inFlight.remove(key)
        entries[key] = .missing(since: Date())
        print("[Jukebox motion] no animated cover for \(key): \(note)")
    }

    private func setCurrentVideo(_ url: URL?) {
        if currentVideo != url {
            currentVideo = url
        }
    }

    private func saveReady() {
        var ready: [String: String] = [:]
        for (key, entry) in entries {
            if case .ready(let fileName) = entry { ready[key] = fileName }
        }
        UserDefaults.standard.set(ready, forKey: readyStorageKey)
    }
}
