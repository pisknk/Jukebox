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
    
    /// the filtered + sorted list, cached so it's only rebuilt when something it depends on changes
    @State private var displayedSongs: [MPMediaItem] = []
    
    private func refreshDisplayedSongs() {
        var songs = musicManager.songs
        
        // apply search filter
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            songs = songs.filter { song in
                (song.title?.localizedCaseInsensitiveContains(query) ?? false) ||
                (song.artist?.localizedCaseInsensitiveContains(query) ?? false) ||
                (song.albumTitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        
        // apply sorting. read each sort key once up front: media item properties are slow to read
        let ascending = sortOrder == .ascending
        switch filterType {
        case .dateAdded:
            let keyed = songs.map { ($0.dateAdded, $0) }
            songs = keyed.sorted { ascending ? $0.0 < $1.0 : $0.0 > $1.0 }.map(\.1)
        case .songName, .albumName, .artistName:
            let keyed: [(String, MPMediaItem)] = songs.map { song in
                switch filterType {
                case .albumName: return (song.albumTitle ?? "", song)
                case .artistName: return (song.artist ?? "", song)
                default: return (song.title ?? "", song)
                }
            }
            songs = keyed.sorted { a, b in
                let result = a.0.localizedStandardCompare(b.0)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }.map(\.1)
        }
        
        displayedSongs = songs
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if AppDesign.isNativeGlass {
                    nativeLayout
                } else {
                    amityLayout
                }
            }
            .toolbar(AppDesign.isNativeGlass ? .automatic : .hidden, for: .navigationBar)
            .onAppear(perform: refreshDisplayedSongs)
            .onChange(of: musicManager.libraryVersion) { _ in refreshDisplayedSongs() }
            .onChange(of: searchText) { _ in refreshDisplayedSongs() }
            .onChange(of: filterType) { _ in refreshDisplayedSongs() }
            .onChange(of: sortOrder) { _ in refreshDisplayedSongs() }
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
                        ArtistDetailView(artistName: artist)
                            .environmentObject(musicManager)
                    }
                }
            }
        }
    }
    
    // MARK: - Layouts

    /// Native Glass: system large title and toolbar buttons (search is its own tab)
    private var nativeLayout: some View {
        libraryContent
            .navigationTitle("Jukebox")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    filterMenu
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        // search lives in the Search tab next to the tab bar
    }

    /// Amity 1.0: custom header with blur and the custom search bar
    private var amityLayout: some View {
        ZStack(alignment: .top) {
            // main scrollable content
            VStack(spacing: 0) {
                // spacer for custom header area
                Color.clear.frame(height: 160)
                
                libraryContent
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
                    filterMenu
                    
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
                if !AppDesign.isNativeGlass {
                    SearchBar(text: $searchText, placeholder: "Search songs, artists, albums")
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if musicManager.hasPermission {
            if musicManager.songs.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    headerButtons
                    songList
                }
            }
        } else {
            permissionDeniedState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filterMenu: some View {
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
                musicManager.playInOrder(songs: displayedSongs, context: "Jukebox")
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
                musicManager.playShuffled(songs: displayedSongs, context: "Jukebox")
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
            ForEach(displayedSongs, id: \.persistentID) { song in
                SongRow(song: song)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // the rest of the queue follows the list as you see it
                        musicManager.play(songs: displayedSongs, startWith: song, context: "Jukebox")
                    }
                    .contextMenu {
                        songContextMenu(for: song)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            }
            
            // bottom spacer for tab bar + mini player
            Color.clear
                .frame(height: AppDesign.legacyBottomSpace(140))
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
    }
    
    private func findAlbum(for song: MPMediaItem) -> MPMediaItemCollection? {
        LibraryQueries.album(containing: song)
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
