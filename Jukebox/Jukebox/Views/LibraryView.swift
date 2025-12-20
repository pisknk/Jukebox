//
//  LibraryView.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import SwiftUI
import MediaPlayer

// MARK: - Filter and Sort Enums
enum SongFilterType: String, CaseIterable {
    case songName = "Song Name"
    case albumName = "Album Name"
    case artistName = "Artist Name"
    case dateAdded = "Date Added"
}

enum SortOrder: String, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"
}

struct LibraryView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var filterType: SongFilterType = .songName
    @State private var sortOrder: SortOrder = .ascending
    
    // context menu states
    @State private var selectedSongForPlaylist: MPMediaItem?
    @State private var showAddToPlaylist = false
    @State private var navigateToArtist: String?
    @State private var navigateToAlbum: MPMediaItemCollection?
    
    private var sortedAndFilteredSongs: [MPMediaItem] {
        var songs = musicManager.songs
        
        // apply search filter
        if !searchText.isEmpty {
            songs = songs.filter { song in
                let titleMatch = song.title?.lowercased().contains(searchText.lowercased()) ?? false
                let artistMatch = song.artist?.lowercased().contains(searchText.lowercased()) ?? false
                let albumMatch = song.albumTitle?.lowercased().contains(searchText.lowercased()) ?? false
                return titleMatch || artistMatch || albumMatch
            }
        }
        
        // apply sorting
        songs.sort { song1, song2 in
            let result: Bool
            switch filterType {
            case .songName:
                result = (song1.title ?? "").localizedCaseInsensitiveCompare(song2.title ?? "") == .orderedAscending
            case .albumName:
                result = (song1.albumTitle ?? "").localizedCaseInsensitiveCompare(song2.albumTitle ?? "") == .orderedAscending
            case .artistName:
                result = (song1.artist ?? "").localizedCaseInsensitiveCompare(song2.artist ?? "") == .orderedAscending
            case .dateAdded:
                // use releaseDate as fallback since dateAdded may not be available
                let date1 = song1.value(forProperty: MPMediaItemPropertyDateAdded) as? Date ?? song1.releaseDate ?? Date.distantPast
                let date2 = song2.value(forProperty: MPMediaItemPropertyDateAdded) as? Date ?? song2.releaseDate ?? Date.distantPast
                result = date1 < date2
            }
            return sortOrder == .ascending ? result : !result
        }
        
        return songs
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // main scrollable content
                VStack(spacing: 0) {
                    // spacer for custom header area
                    Color.clear.frame(height: 160)
                    
                    if musicManager.hasPermission {
                        if musicManager.songs.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 0) {
                                headerButtons
                                songList
                            }
                        }
                    } else {
                        permissionDeniedState
                    }
                }
                
                // gradient blur header overlay
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 180)
                        .background(
                            .ultraThinMaterial
                        )
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black, location: 0.6),
                                    .init(color: .black.opacity(0.7), location: 0.75),
                                    .init(color: .black.opacity(0.3), location: 0.9),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // custom header content
                VStack(spacing: 0) {
                    // status bar spacer
                    Color.clear.frame(height: 50)
                    
                    // title row with buttons
                    HStack(alignment: .center) {
                        Text("Jukebox")
                            .font(.system(size: 34, weight: .bold))
                        
                        Spacer()
                        
                        // filter menu
                        Menu {
                            Section("Filter By") {
                                Menu {
                                    Button(action: { filterType = .songName }) {
                                        Label("Song Name", systemImage: "music.note")
                                    }
                                    Button(action: { filterType = .albumName }) {
                                        Label("Album Name", systemImage: "square.stack")
                                    }
                                    Button(action: { filterType = .artistName }) {
                                        Label("Artist Name", systemImage: "person")
                                    }
                                } label: {
                                    Label("Name", systemImage: "textformat")
                                }
                                Button(action: { filterType = .dateAdded }) {
                                    Label("Date Added", systemImage: "calendar")
                                }
                            }
                            
                            Section("Sort By") {
                                Button(action: { sortOrder = .ascending }) {
                                    Label("Ascending", systemImage: "arrow.up")
                                }
                                Button(action: { sortOrder = .descending }) {
                                    Label("Descending", systemImage: "arrow.down")
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 22))
                                .foregroundColor(.primary)
                        }
                        
                        // settings button
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    
                    // search bar
                    SearchBar(text: $searchText, placeholder: "Search songs, artists, albums")
                        .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAddToPlaylist) {
                addToPlaylistSheet
            }
            .sheet(item: $navigateToAlbum) { album in
                NavigationView {
                    AlbumDetailView(album: album)
                        .environmentObject(musicManager)
                }
            }
            .sheet(isPresented: artistNavigationBinding) {
                if let artist = navigateToArtist {
                    NavigationView {
                        ArtistDetailView(
                            artistName: artist,
                            artistAlbums: musicManager.albums.filter { $0.representativeItem?.artist == artist }
                        )
                        .environmentObject(musicManager)
                    }
                }
            }
        }
    }
    
    private var addToPlaylistSheet: some View {
        Group {
            if let song = selectedSongForPlaylist {
                AddToPlaylistView(song: song)
                    .environmentObject(musicManager)
            }
        }
    }
    
    private var artistNavigationBinding: Binding<Bool> {
        Binding(
            get: { navigateToArtist != nil },
            set: { if !$0 { navigateToArtist = nil } }
        )
    }
    
    private var headerButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                if let firstSong = sortedAndFilteredSongs.first {
                    musicManager.play(song: firstSong)
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                    Text("Play All")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(red: 0.25, green: 0.15, blue: 0.35))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                // enable shuffle mode and play
                if !musicManager.shuffleEnabled {
                    musicManager.toggleShuffle()
                }
                if let randomSong = sortedAndFilteredSongs.randomElement() {
                    musicManager.play(song: randomSong)
                }
            }) {
                HStack {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16))
                    Text("Shuffle")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(red: 0.25, green: 0.15, blue: 0.35))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
    
    private var songList: some View {
        List {
            ForEach(sortedAndFilteredSongs, id: \.persistentID) { song in
                SongRow(song: song)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        musicManager.play(song: song)
                    }
                    .contextMenu {
                        songContextMenu(for: song)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
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
    
    @ViewBuilder
    private func songContextMenu(for song: MPMediaItem) -> some View {
        Button {
            musicManager.addToQueue(song: song)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        
        Button {
            selectedSongForPlaylist = song
            showAddToPlaylist = true
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
        
        if let artist = song.artist {
            Button {
                navigateToArtist = artist
            } label: {
                Label("Go to \(artist)", systemImage: "person.fill")
            }
        }
        
        if let albumTitle = song.albumTitle {
            Button {
                if let album = findAlbum(for: song) {
                    navigateToAlbum = album
                }
            } label: {
                Label("Go to \(albumTitle)", systemImage: "square.stack")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            // note: iOS doesn't allow deleting songs from library via API
            // this is a placeholder that shows unavailable
        } label: {
            Label("Delete from Library", systemImage: "trash")
        }
        .disabled(true)
    }
    
    private func findAlbum(for song: MPMediaItem) -> MPMediaItemCollection? {
        guard let albumTitle = song.albumTitle else { return nil }
        return musicManager.albums.first(where: {
            $0.representativeItem?.albumTitle == albumTitle &&
            $0.representativeItem?.albumArtist == song.albumArtist
        })
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Songs Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Sync music to your device using iTunes or the Music app")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var permissionDeniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("Media Library Access Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Please allow access to your media library in Settings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Extensions
extension MPMediaItemCollection: @retroactive Identifiable {
    public var id: UInt64 {
        return persistentID
    }
}


// MARK: - Settings View


// MARK: - Song Row Component
struct SongRow: View {
    let song: MPMediaItem
    
    var body: some View {
        HStack(spacing: 12) {
            // album artwork
            if let artwork = song.artwork {
                if let image = artwork.image(at: CGSize(width: 60, height: 60)) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                } else {
                    placeholderArtwork
                }
            } else {
                placeholderArtwork
            }
            
            // song info
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title ?? "Unknown Title")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(song.artist ?? "Unknown Artist")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let album = song.albumTitle {
                        Text("•")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text(album)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // duration
            if song.playbackDuration > 0 {
                Text(formatDuration(song.playbackDuration))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
            
            Image(systemName: "music.note")
                .font(.system(size: 24))
                .foregroundColor(.gray)
        }
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
