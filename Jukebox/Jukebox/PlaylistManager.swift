//
//  PlaylistManager.swift
//  Jukebox
//
//  Manages custom playlists with full CRUD operations.
//

import Foundation
import SwiftUI
import MediaPlayer

// MARK: - Playlist Model
struct CustomPlaylist: Identifiable, Codable {
    let id: UUID
    var name: String
    var songPersistentIDs: [UInt64]
    var coverImageData: Data?
    var dateCreated: Date
    
    init(id: UUID = UUID(), name: String, songPersistentIDs: [UInt64] = [], coverImageData: Data? = nil) {
        self.id = id
        self.name = name
        self.songPersistentIDs = songPersistentIDs
        self.coverImageData = coverImageData
        self.dateCreated = Date()
    }
    
    // get cover image from data or first song
    func getCoverImage(songs: [MPMediaItem]) -> UIImage? {
        if let data = coverImageData, let image = UIImage(data: data) {
            return image
        }
        // use first song's artwork
        if let firstID = songPersistentIDs.first,
           let song = songs.first(where: { $0.persistentID == firstID }),
           let artwork = song.artwork {
            return artwork.image(at: CGSize(width: 200, height: 200))
        }
        return nil
    }
    
    // get songs from persistent IDs
    func getSongs(from allSongs: [MPMediaItem]) -> [MPMediaItem] {
        return songPersistentIDs.compactMap { id in
            allSongs.first(where: { $0.persistentID == id })
        }
    }
}

// MARK: - Playlist Manager
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()
    
    @Published var playlists: [CustomPlaylist] = []
    
    private let storageKey = "custom_playlists"
    
    private init() {
        loadPlaylists()
    }
    
    // MARK: - CRUD Operations
    
    func createPlaylist(name: String, coverImage: UIImage? = nil) -> CustomPlaylist {
        let coverData = coverImage?.jpegData(compressionQuality: 0.8)
        let playlist = CustomPlaylist(name: name, coverImageData: coverData)
        playlists.insert(playlist, at: 0)
        savePlaylists()
        return playlist
    }
    
    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }
    
    func renamePlaylist(id: UUID, name: String) {
        if let index = playlists.firstIndex(where: { $0.id == id }) {
            playlists[index].name = name
            savePlaylists()
        }
    }
    
    func setCover(for playlistID: UUID, image: UIImage?) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].coverImageData = image?.jpegData(compressionQuality: 0.8)
            savePlaylists()
        }
    }
    
    // MARK: - Song Operations
    
    func addSong(to playlistID: UUID, songID: UInt64) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            if !playlists[index].songPersistentIDs.contains(songID) {
                playlists[index].songPersistentIDs.append(songID)
                savePlaylists()
            }
        }
    }
    
    func removeSong(from playlistID: UUID, at songIndex: Int) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            guard songIndex < playlists[index].songPersistentIDs.count else { return }
            playlists[index].songPersistentIDs.remove(at: songIndex)
            savePlaylists()
        }
    }
    
    func moveSong(in playlistID: UUID, from source: IndexSet, to destination: Int) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].songPersistentIDs.move(fromOffsets: source, toOffset: destination)
            savePlaylists()
        }
    }
    
    func setCoverImage(_ imageData: Data?, for playlistID: UUID) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].coverImageData = imageData
            savePlaylists()
        }
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
