//
//  CollectionsView.swift
//  Jukebox
//
//  Collections view showing categories like Playlists, Albums, Artists, etc.
//

import SwiftUI
import MediaPlayer

struct CollectionsView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @ObservedObject var playlistManager = PlaylistManager.shared
    
    // collection categories
    private let categories: [(name: String, icon: String, color: Color)] = [
        ("Playlists", "music.note.list", .pink),
        ("Albums", "square.stack", .pink),
        ("Favourites", "star.fill", .pink),
        ("Artists", "music.mic", .pink),
        ("Songs", "music.note", .pink)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // category list
                    VStack(spacing: 0) {
                        ForEach(categories, id: \.name) { category in
                            NavigationLink(destination: categoryDestination(for: category.name)) {
                                HStack(spacing: 16) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(category.color)
                                        .frame(width: 30)
                                    
                                    Text(category.name)
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 20)
                            }
                            
                            if category.name != categories.last?.name {
                                Divider()
                                    .padding(.leading, 66)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    
                    // recently added albums
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recently added")
                            .font(.system(size: 22, weight: .bold))
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(recentlyAddedAlbums, id: \.persistentID) { album in
                                    RecentAlbumCard(album: album)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // recently created playlists
                    if !playlistManager.recentlyCreated().isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Recently created")
                                .font(.system(size: 22, weight: .bold))
                                .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(playlistManager.recentlyCreated()) { playlist in
                                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                            ZStack(alignment: .bottom) {
                                                // cover art
                                                if let img = playlist.getCoverImage(songs: musicManager.songs) {
                                                    Image(uiImage: img)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 170, height: 200)
                                                        .clipped()
                                                } else {
                                                    ZStack {
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .fill(LinearGradient(
                                                                colors: [.pink.opacity(0.4), .purple.opacity(0.4)],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ))
                                                            .frame(width: 170, height: 200)
                                                        Image(systemName: "music.note.list")
                                                            .font(.system(size: 40))
                                                            .foregroundColor(.white)
                                                    }
                                                }
                                                
                                                // fixed height blur overlay at bottom
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(playlist.name)
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundColor(.white)
                                                        .lineLimit(1)
                                                    
                                                    Text("\(playlist.songPersistentIDs.count) songs")
                                                        .font(.system(size: 13))
                                                        .foregroundColor(.white.opacity(0.7))
                                                        .lineLimit(1)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.top, 60)
                                                .padding(.bottom, 10)
                                                .frame(width: 170, alignment: .leading)
                                                .background(
                                                    Rectangle()
                                                        .fill(.ultraThinMaterial)
                                                        .mask(
                                                            LinearGradient(
                                                                stops: [
                                                                    .init(color: .clear, location: 0.0),
                                                                    .init(color: .black.opacity(0.5), location: 0.3),
                                                                    .init(color: .black, location: 0.6),
                                                                    .init(color: .black, location: 1.0)
                                                                ],
                                                                startPoint: .top,
                                                                endPoint: .bottom
                                                            )
                                                        )
                                                )
                                            }
                                            .frame(width: 170, height: 200)
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Library")
        }
    }
    
    // get recently added albums
    private var recentlyAddedAlbums: [MPMediaItemCollection] {
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: false,
            forProperty: MPMediaItemPropertyIsCloudItem
        ))
        
        guard let collections = query.collections else { return [] }
        
        // sort by date added (if available) and take first 10
        let sorted = collections.sorted { a, b in
            let dateA = a.representativeItem?.dateAdded ?? Date.distantPast
            let dateB = b.representativeItem?.dateAdded ?? Date.distantPast
            return dateA > dateB
        }
        
        return Array(sorted.prefix(10))
    }
    
    @ViewBuilder
    private func categoryDestination(for name: String) -> some View {
        switch name {
        case "Playlists":
            PlaylistsListView()
        case "Albums":
            AlbumsListView()
        case "Artists":
            ArtistsListView()
        case "Songs":
            SongsListView()
        case "Favourites":
            FavouritesView()
        default:
            Text("Coming soon")
        }
    }
}

// MARK: - Recent Album Card
struct RecentAlbumCard: View {
    let album: MPMediaItemCollection
    
    var body: some View {
        NavigationLink(destination: AlbumDetailView(album: album)) {
            ZStack(alignment: .bottom) {
                // album artwork
                if let artwork = album.representativeItem?.artwork,
                   let image = artwork.image(at: CGSize(width: 200, height: 200)) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 170, height: 200)
                        .clipped()
                } else {
                    placeholderArtwork
                }
                
                // fixed height blur overlay at bottom
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.representativeItem?.albumTitle ?? "Unknown Album")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(album.representativeItem?.artist ?? "Unknown Artist")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 60)
                .padding(.bottom, 10)
                .frame(width: 170, alignment: .leading)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black.opacity(0.5), location: 0.3),
                                    .init(color: .black, location: 0.6),
                                    .init(color: .black, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .frame(width: 170, height: 200)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 170, height: 200)
            
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Playlists List View
struct PlaylistsListView: View {
    @ObservedObject var playlistManager = PlaylistManager.shared
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var showCreatePlaylist = false
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // search bar
            SearchBar(text: $searchText, placeholder: "Search playlists...")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            List {
                // New Playlist Button
                Button(action: {
                    showCreatePlaylist = true
                }) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.pink.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "plus")
                                .font(.system(size: 24))
                                .foregroundColor(.pink)
                        }
                        Text("New Playlist...")
                            .font(.system(size: 17))
                            .foregroundColor(.pink)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                // Custom Playlists (Editable) - filtered
                let filteredCustom = searchText.isEmpty ? playlistManager.playlists : playlistManager.playlists.filter {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                }
                if !filteredCustom.isEmpty {
                    Section(header: Text("My Playlists")) {
                        ForEach(filteredCustom) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                HStack(spacing: 12) {
                                    if let img = playlist.getCoverImage(songs: musicManager.songs) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 50, height: 50)
                                            .cornerRadius(6)
                                    } else {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(LinearGradient(
                                                    colors: [.pink.opacity(0.4), .purple.opacity(0.4)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ))
                                                .frame(width: 50, height: 50)
                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name)
                                            .font(.system(size: 16, weight: .medium))
                                        Text("\(playlist.songPersistentIDs.count) songs")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let playlist = filteredCustom[index]
                                playlistManager.deletePlaylist(id: playlist.id)
                            }
                        }
                    }
                }
                
                // Apple Music Playlists (Read Only) - filtered
                let allApple = MPMediaQuery.playlists().collections ?? []
                let filteredApple = searchText.isEmpty ? allApple : allApple.filter { playlist in
                    let name = playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? ""
                    return name.localizedCaseInsensitiveContains(searchText)
                }
                if !filteredApple.isEmpty {
                    Section(header: Text("Apple Music Playlists")) {
                        ForEach(filteredApple, id: \.persistentID) { playlist in
                            HStack(spacing: 12) {
                                if let artwork = playlist.representativeItem?.artwork,
                                   let image = artwork.image(at: CGSize(width: 50, height: 50)) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(6)
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "music.note.list")
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Playlist")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("\(playlist.count) songs")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // bottom spacer for tab bar + mini player
                Section {
                    Color.clear
                        .frame(height: 100)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.grouped)
        }
        .navigationTitle("Playlists")
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistView()
        }
    }
}

// MARK: - Albums List View
struct AlbumsListView: View {
    @State private var searchText = ""
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        let query = MPMediaQuery.albums()
        let allAlbums = query.collections ?? []
        
        // filter albums based on search
        let albums = searchText.isEmpty ? allAlbums : allAlbums.filter { album in
            let title = album.representativeItem?.albumTitle ?? ""
            let artist = album.representativeItem?.artist ?? ""
            return title.localizedCaseInsensitiveContains(searchText) ||
                   artist.localizedCaseInsensitiveContains(searchText)
        }
        
        ScrollView {
            // search bar
            SearchBar(text: $searchText, placeholder: "Search albums...")
                .padding(.horizontal, 20)
                .padding(.top, 8)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums, id: \.persistentID) { album in
                    RecentAlbumCard(album: album)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // bottom spacer for tab bar + mini player
            Color.clear
                .frame(height: 140)
        }
        .navigationTitle("Albums")
    }
}

// MARK: - Artists List View
struct ArtistsListView: View {
    @State private var searchText = ""
    
    var body: some View {
        let query = MPMediaQuery.artists()
        let allArtists = query.collections ?? []
        
        // filter artists based on search
        let artists = searchText.isEmpty ? allArtists : allArtists.filter { artist in
            let name = artist.representativeItem?.artist ?? ""
            return name.localizedCaseInsensitiveContains(searchText)
        }
        
        VStack(spacing: 0) {
            // search bar
            SearchBar(text: $searchText, placeholder: "Search artists...")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            List {
                ForEach(artists, id: \.persistentID) { artist in
                    let artistName = artist.representativeItem?.artist ?? "Unknown Artist"
                    NavigationLink(destination: ArtistDetailView(
                        artistName: artistName,
                        artistAlbums: getAlbums(for: artistName)
                    )) {
                        ArtistRowView(artistName: artistName, songCount: artist.count)
                    }
                }
                
                // bottom spacer for tab bar + mini player
                Color.clear
                    .frame(height: 140)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
        .navigationTitle("Artists")
    }
    
    func getAlbums(for artist: String) -> [MPMediaItemCollection] {
        let query = MPMediaQuery.albums()
        let predicate = MPMediaPropertyPredicate(value: artist, forProperty: MPMediaItemPropertyArtist)
        query.addFilterPredicate(predicate)
        return query.collections ?? []
    }
}

// MARK: - Artist Row View
struct ArtistRowView: View {
    let artistName: String
    let songCount: Int
    @State private var imageURL: URL?
    @State private var isLoading = true
    
    var body: some View {
        HStack(spacing: 12) {
            artistImage
            
            VStack(alignment: .leading, spacing: 4) {
                Text(artistName)
                    .font(.system(size: 16, weight: .medium))
                Text("\(songCount) songs")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    @ViewBuilder
    private var artistImage: some View {
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                case .failure:
                    placeholderImage
                case .empty:
                    ProgressView()
                        .frame(width: 50, height: 50)
                @unknown default:
                    placeholderImage
                }
            }
        } else if isLoading {
            ProgressView()
                .frame(width: 50, height: 50)
        } else {
            placeholderImage
        }
    }
    
    private var placeholderImage: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.15))
                .frame(width: 50, height: 50)
            Image(systemName: "music.mic")
                .foregroundColor(.pink)
        }
    }
    
    private func loadImage() {
        ArtistImageManager.shared.getArtistImage(name: artistName) { url in
            self.imageURL = url
            self.isLoading = false
        }
    }
}

// MARK: - Songs List View
struct SongsListView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var showAddToPlaylist = false
    @State private var selectedSong: MPMediaItem?
    @State private var searchText: String = ""
    
    private var filteredSongs: [MPMediaItem] {
        if searchText.isEmpty {
            return musicManager.songs
        }
        return musicManager.songs.filter { song in
            (song.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (song.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (song.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // search bar
            SearchBar(text: $searchText, placeholder: "Search songs...")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            List {
                // play/shuffle buttons
                Section {
                    HStack(spacing: 12) {
                        Button(action: {
                            if let first = filteredSongs.first {
                                musicManager.shuffleEnabled = false
                                musicManager.play(songs: filteredSongs, startWith: first, context: "Songs")
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            musicManager.shuffleEnabled = true
                            if let randomSong = filteredSongs.randomElement() {
                                musicManager.play(songs: filteredSongs, startWith: randomSong, context: "Songs")
                            }
                        }) {
                            HStack {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                
                // songs list
                Section {
                    ForEach(filteredSongs, id: \.persistentID) { song in
                        SongRow(song: song)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                musicManager.play(songs: filteredSongs, startWith: song, context: "Songs")
                            }
                            .contextMenu {
                                Button(action: {
                                    selectedSong = song
                                    showAddToPlaylist = true
                                }) {
                                    Label("Add to Playlist", systemImage: "plus.circle")
                                }
                            }
                    }
                }
                
                // bottom spacer for tab bar + mini player
                Section {
                    Color.clear
                        .frame(height: 100)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Songs")
        .sheet(item: $selectedSong) { song in
            AddToPlaylistView(song: song)
        }
    }
}

// Extension to make MPMediaItem Identifiable for sheet
extension MPMediaItem: @retroactive Identifiable {
    public var id: UInt64 { persistentID }
}

// MARK: - Favourites View
struct FavouritesView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var searchText = ""
    
    private var favoriteSongs: [MPMediaItem] {
        let allFavorites = favoritesManager.getFavoriteSongs(from: musicManager.songs)
        if searchText.isEmpty { return allFavorites }
        return allFavorites.filter { song in
            (song.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (song.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (song.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // search bar
            SearchBar(text: $searchText, placeholder: "Search favourites...")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            Group {
                if favoriteSongs.isEmpty && searchText.isEmpty {
                    emptyStateView
                } else {
                    favoritesListView
                }
            }
        }
        .navigationTitle("Favourites")
    }
    
    private var favoritesListView: some View {
        List {
            // play/shuffle buttons section
            Section {
                HStack(spacing: 12) {
                    Button(action: {
                        if let first = favoriteSongs.first {
                            musicManager.play(songs: favoriteSongs, startWith: first, context: "Favourites")
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        musicManager.shuffleEnabled = true
                        if let randomSong = favoriteSongs.randomElement() {
                            musicManager.play(songs: favoriteSongs, startWith: randomSong, context: "Favourites")
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            
            // songs section
            Section {
                ForEach(favoriteSongs, id: \.persistentID) { song in
                    FavoriteSongRow(song: song, favoritesManager: favoritesManager, musicManager: musicManager, allSongs: favoriteSongs)
                }
            }
            
            // bottom spacer for tab bar + mini player
            Section {
                Color.clear
                    .frame(height: 100)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Favourites Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Songs you mark as favourite will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Favorite Song Row
struct FavoriteSongRow: View {
    let song: MPMediaItem
    let favoritesManager: FavoritesManager
    let musicManager: MusicPlayerManager
    let allSongs: [MPMediaItem]
    
    var body: some View {
        Button(action: {
            musicManager.play(songs: allSongs, startWith: song, context: "Favourites")
        }) {
            HStack(spacing: 12) {
                songArtwork
                songInfo
                Spacer()
                unfavoriteButton
            }
        }
        .buttonStyle(.plain)
    }
    
    private var songArtwork: some View {
        Group {
            if let artwork = song.artwork,
               let image = artwork.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
            }
        }
    }
    
    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title ?? "Unknown")
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(song.artist ?? "Unknown Artist")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
    
    private var unfavoriteButton: some View {
        Button(action: {
            favoritesManager.toggleFavorite(song.persistentID)
        }) {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
    }
}

