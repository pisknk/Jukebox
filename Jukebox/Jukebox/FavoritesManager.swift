//
//  FavoritesManager.swift
//  Jukebox
//
//  manages favorited songs with persistent storage
//

import Foundation
import MediaPlayer
import Combine

final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published private(set) var favoriteSongIDs: Set<UInt64> = []

    /// stored as JSON: song ids use the full unsigned 64-bit range, which JSON keeps exactly
    private let storageKey = "favorited_songs_v2"
    private let legacyStorageKey = "favorited_songs"

    private init() {
        loadFavorites()
    }

    // MARK: - favorites operations

    func isFavorite(_ songID: UInt64) -> Bool {
        return favoriteSongIDs.contains(songID)
    }

    func toggleFavorite(_ songID: UInt64) {
        if favoriteSongIDs.contains(songID) {
            favoriteSongIDs.remove(songID)
        } else {
            favoriteSongIDs.insert(songID)
        }
        saveFavorites()
    }

    func getFavoriteSongs(from allSongs: [MPMediaItem]) -> [MPMediaItem] {
        return allSongs.filter { favoriteSongIDs.contains($0.persistentID) }
    }

    // MARK: - persistence

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favoriteSongIDs)) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let ids = try? JSONDecoder().decode([UInt64].self, from: data) {
            favoriteSongIDs = Set(ids)
            return
        }

        // older versions stored a plain number array. ids above Int64.max can come back
        // as negative numbers, which made `as? [UInt64]` fail and lose every favorite.
        // reading each one as NSNumber and taking its unsigned bit pattern recovers them.
        if let legacy = UserDefaults.standard.array(forKey: legacyStorageKey) {
            let ids = legacy.compactMap { ($0 as? NSNumber)?.uint64Value }
            favoriteSongIDs = Set(ids)
            saveFavorites()
        }
    }
}
