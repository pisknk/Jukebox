//
//  PlaylistManager.swift
//  Jukebox
//
//  Manages custom playlists with full CRUD operations.
//  Playlist data lives in UserDefaults; cover images are files in Application Support.
//

import Foundation
import SwiftUI
import MediaPlayer

// MARK: - Playlist Model
struct CustomPlaylist: Identifiable, Codable {
    let id: UUID
    var name: String
    var songPersistentIDs: [UInt64]
    /// only used to migrate covers saved by older versions; new covers are files
    var coverImageData: Data?
    var coverFileName: String?
    var dateCreated: Date

    init(id: UUID = UUID(), name: String, songPersistentIDs: [UInt64] = []) {
        self.id = id
        self.name = name
        self.songPersistentIDs = songPersistentIDs
        self.coverImageData = nil
        self.coverFileName = nil
        self.dateCreated = Date()
    }
}

/// a playlist song that's on this device, with its position in the saved list
struct PlaylistRow: Identifiable {
    let storedIndex: Int
    let song: MPMediaItem
    var id: UInt64 { song.persistentID }
}

// MARK: - Playlist Manager
final class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published private(set) var playlists: [CustomPlaylist] = []

    private let storageKey = "custom_playlists"
    private let coversDirectory: URL
    private let coverCache = NSCache<NSString, UIImage>()
    private let maxCoverSize: CGFloat = 800

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        coversDirectory = support.appendingPathComponent("PlaylistCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        loadPlaylists()
        migrateInlineCovers()
    }

    func playlist(id: UUID) -> CustomPlaylist? {
        playlists.first { $0.id == id }
    }

    // MARK: - CRUD Operations

    @discardableResult
    func createPlaylist(name: String) -> CustomPlaylist {
        let playlist = CustomPlaylist(name: name)
        playlists.insert(playlist, at: 0)
        savePlaylists()
        return playlist
    }

    func deletePlaylist(id: UUID) {
        if let fileName = playlist(id: id)?.coverFileName {
            removeCoverFile(fileName)
        }
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func renamePlaylist(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = trimmed
        savePlaylists()
    }

    // MARK: - Covers

    /// saves a custom cover (resized), or removes it when `image` is nil
    func setCoverImage(_ image: UIImage?, for playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }

        if let old = playlists[index].coverFileName {
            removeCoverFile(old)
        }
        playlists[index].coverFileName = nil
        playlists[index].coverImageData = nil

        if let image = image, let data = resized(image).jpegData(compressionQuality: 0.85) {
            // new name each time so cached images never go stale
            let fileName = "\(playlistID.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
            do {
                try data.write(to: coversDirectory.appendingPathComponent(fileName), options: .atomic)
                playlists[index].coverFileName = fileName
            } catch {
                print("failed to save playlist cover: \(error.localizedDescription)")
            }
        }
        savePlaylists()
    }

    /// the custom cover if there is one, otherwise the first available song's artwork
    func coverImage(for playlist: CustomPlaylist, songsByID: [UInt64: MPMediaItem]) -> UIImage? {
        if let fileName = playlist.coverFileName {
            if let cached = coverCache.object(forKey: fileName as NSString) {
                return cached
            }
            if let image = UIImage(contentsOfFile: coversDirectory.appendingPathComponent(fileName).path) {
                coverCache.setObject(image, forKey: fileName as NSString)
                return image
            }
        }
        for id in playlist.songPersistentIDs {
            if let artwork = songsByID[id]?.artwork {
                return artwork.image(at: CGSize(width: 300, height: 300))
            }
        }
        return nil
    }

    private func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxCoverSize else { return image }
        let scale = maxCoverSize / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func removeCoverFile(_ fileName: String) {
        coverCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(fileName))
    }

    /// older versions stored covers inside UserDefaults, which can grow past iOS's size limit
    private func migrateInlineCovers() {
        var changed = false
        for index in playlists.indices {
            guard let data = playlists[index].coverImageData else { continue }
            if let image = UIImage(data: data),
               let jpeg = resized(image).jpegData(compressionQuality: 0.85) {
                let fileName = "\(playlists[index].id.uuidString)-migrated.jpg"
                if (try? jpeg.write(to: coversDirectory.appendingPathComponent(fileName), options: .atomic)) != nil {
                    playlists[index].coverFileName = fileName
                }
            }
            playlists[index].coverImageData = nil
            changed = true
        }
        if changed { savePlaylists() }
    }

    // MARK: - Songs

    /// songs in the playlist that are on this device, with their saved positions
    func rows(for playlistID: UUID, songsByID: [UInt64: MPMediaItem]) -> [PlaylistRow] {
        guard let playlist = playlist(id: playlistID) else { return [] }
        let stored = playlist.songPersistentIDs
        return PlaylistOrdering.visibleIndices(storedIDs: stored, isAvailable: { songsByID[$0] != nil })
            .compactMap { index in
                songsByID[stored[index]].map { PlaylistRow(storedIndex: index, song: $0) }
            }
    }

    func addSong(to playlistID: UUID, songID: UInt64) {
        addSongs(to: playlistID, songIDs: [songID])
    }

    /// adds in the given order, skipping songs already in the playlist
    func addSongs(to playlistID: UUID, songIDs: [UInt64]) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var existing = Set(playlists[index].songPersistentIDs)
        for id in songIDs where !existing.contains(id) {
            playlists[index].songPersistentIDs.append(id)
            existing.insert(id)
        }
        savePlaylists()
    }

    /// `storedIndices` are positions in the saved list (`PlaylistRow.storedIndex`)
    func removeSongs(from playlistID: UUID, storedIndices: IndexSet) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songPersistentIDs = ArrayEditing.removing(playlists[index].songPersistentIDs, atOffsets: storedIndices)
        savePlaylists()
    }

    /// `source`/`destination` are positions among the visible rows
    func moveVisibleSongs(in playlistID: UUID, rows: [PlaylistRow], from source: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songPersistentIDs = PlaylistOrdering.applyingVisibleMove(
            storedIDs: playlists[index].songPersistentIDs,
            visibleIndices: rows.map(\.storedIndex),
            from: source,
            to: destination
        )
        savePlaylists()
    }

    // MARK: - Recently Created

    func recentlyCreated(limit: Int = 5) -> [CustomPlaylist] {
        return Array(playlists.sorted { $0.dateCreated > $1.dateCreated }.prefix(limit))
    }

    // MARK: - Persistence

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadPlaylists() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([CustomPlaylist].self, from: data) {
            playlists = saved
        }
    }
}
