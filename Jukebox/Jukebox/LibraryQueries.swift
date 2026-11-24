//
//  LibraryQueries.swift
//  Jukebox
//
//  media library lookups shared by the views. these hit the library database, so views
//  should call them once (onAppear / when the library changes), not from `body`.
//

import Foundation
import MediaPlayer

enum LibraryQueries {
    /// only items stored on this device
    private static var localOnly: MPMediaPropertyPredicate {
        MPMediaPropertyPredicate(value: false, forProperty: MPMediaItemPropertyIsCloudItem)
    }

    static func allAlbums() -> [MPMediaItemCollection] {
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(localOnly)
        return query.collections ?? []
    }

    static func allArtists() -> [MPMediaItemCollection] {
        let query = MPMediaQuery.artists()
        query.addFilterPredicate(localOnly)
        return query.collections ?? []
    }

    /// albums with at least one song by this artist (includes compilations they appear on)
    static func albums(forArtist artist: String) -> [MPMediaItemCollection] {
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(localOnly)
        query.addFilterPredicate(MPMediaPropertyPredicate(value: artist, forProperty: MPMediaItemPropertyArtist))
        return query.collections ?? []
    }

    /// the full album a song belongs to
    static func album(containing song: MPMediaItem) -> MPMediaItemCollection? {
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(localOnly)
        query.addFilterPredicate(MPMediaPropertyPredicate(value: song.albumPersistentID, forProperty: MPMediaItemPropertyAlbumPersistentID))
        return query.collections?.first
    }

    static func recentlyAddedAlbums(limit: Int) -> [MPMediaItemCollection] {
        let albums = allAlbums().map { album -> (Date, MPMediaItemCollection) in
            // newest song in the album, not just the first one
            let newest = album.items.map(\.dateAdded).max() ?? .distantPast
            return (newest, album)
        }
        return albums.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    static func appleMusicPlaylists() -> [MPMediaPlaylist] {
        (MPMediaQuery.playlists().collections ?? []).compactMap { $0 as? MPMediaPlaylist }
    }

    /// playable (downloaded, non-DRM) songs in a collection
    static func playableItems(_ collection: MPMediaItemCollection) -> [MPMediaItem] {
        collection.items.filter { $0.assetURL != nil }
    }
}
