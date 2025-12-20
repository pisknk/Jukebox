//
//  FavoritesManager.swift
//  Jukebox
//
//  manages favorited songs with persistent storage
//

import Foundation
import MediaPlayer
import Combine

class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    
    @Published var favoriteSongIDs: Set<UInt64> = []
    
    private let storageKey = "favorited_songs"
    
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
        let array = Array(favoriteSongIDs)
        UserDefaults.standard.set(array, forKey: storageKey)
    }
    
    private func loadFavorites() {
        if let array = UserDefaults.standard.array(forKey: storageKey) as? [UInt64] {
            favoriteSongIDs = Set(array)
        }
    }
}
