//
//  LibrarySearchView.swift
//  Jukebox
//
//  The Search tab in Native Glass: the round search button next to the tab bar.
//  Searches songs, albums and artists in the library.
//

import SwiftUI
import MediaPlayer

@available(iOS 26, *)
struct LibrarySearchView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var query = ""
    @State private var allAlbums: [MPMediaItemCollection] = []
    @State private var allArtists: [MPMediaItemCollection] = []
    @State private var selectedSongForPlaylist: MPMediaItem?

    private let maxSongs = 50
    private let maxCollections = 20

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var songResults: [MPMediaItem] {
        guard !trimmedQuery.isEmpty else { return [] }
        return Array(musicManager.songs.lazy.filter { song in
            (song.title?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            (song.artist?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            (song.albumTitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }.prefix(maxSongs))
    }

    private var albumResults: [MPMediaItemCollection] {
        guard !trimmedQuery.isEmpty else { return [] }
        return Array(allAlbums.lazy.filter { album in
            (album.representativeItem?.albumTitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            (album.representativeItem?.albumArtist?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }.prefix(maxCollections))
    }

    private var artistResults: [String] {
        guard !trimmedQuery.isEmpty else { return [] }
        return Array(allArtists.lazy
            .compactMap { $0.representativeItem?.artist }
            .filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            .prefix(maxCollections))
    }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Search Your Library",
                        systemImage: "magnifyingglass",
                        description: Text("Find songs, albums and artists.")
                    )
                } else {
                    results
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Songs, artists, albums")
            .onAppear(perform: loadCollections)
            .onChange(of: musicManager.libraryVersion) { _ in
                allAlbums = []
                allArtists = []
                loadCollections()
            }
            .sheet(item: $selectedSongForPlaylist) { song in
                AddToPlaylistView(song: song)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let songs = songResults
        let albums = albumResults
        let artists = artistResults

        if songs.isEmpty && albums.isEmpty && artists.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else {
            List {
                if !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists, id: \.self) { artist in
                            NavigationLink(destination: ArtistDetailView(artistName: artist)) {
                                Label(artist, systemImage: "music.mic")
                            }
                        }
                    }
                }

                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums, id: \.persistentID) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                AlbumResultRow(album: album)
                            }
                        }
                    }
                }

                if !songs.isEmpty {
                    Section("Songs") {
                        ForEach(songs, id: \.persistentID) { song in
                            SongRow(song: song)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    musicManager.play(songs: songs, startWith: song, context: "Search")
                                }
                                .contextMenu {
                                    Button {
                                        musicManager.addToQueue(song: song)
                                    } label: {
                                        Label("Add to Queue", systemImage: "text.badge.plus")
                                    }
                                    Button {
                                        selectedSongForPlaylist = song
                                    } label: {
                                        Label("Add to Playlist", systemImage: "music.note.list")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// album and artist lists come from the media library, so load them once
    private func loadCollections() {
        guard musicManager.hasPermission, allAlbums.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let albums = LibraryQueries.allAlbums()
            let artists = LibraryQueries.allArtists()
            DispatchQueue.main.async {
                allAlbums = albums
                allArtists = artists
            }
        }
    }
}

@available(iOS 26, *)
private struct AlbumResultRow: View {
    let album: MPMediaItemCollection

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = album.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: "square.stack")
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(album.representativeItem?.albumTitle ?? "Unknown Album")
                    .lineLimit(1)
                Text(album.representativeItem?.albumArtist ?? album.representativeItem?.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
