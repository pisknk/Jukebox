//
//  ContentView.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import SwiftUI
import MediaPlayer

struct ContentView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var showNowPlaying = false
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    
    // calculate bottom safe area for proper tab bar positioning
    private var tabBarHeight: CGFloat { 49 }
    private var miniPlayerHeight: CGFloat { 64 }
    
    var body: some View {
        GeometryReader { geometry in
            let bottomSafeArea = geometry.safeAreaInsets.bottom
            let totalBottomPadding = tabBarHeight + bottomSafeArea
            
            ZStack(alignment: .bottom) {
                // tab content - add padding at bottom to avoid overlap
                TabView(selection: $selectedTab) {
                    LibraryView()
                        .tag(0)
                    
                    CollectionsView()
                        .tag(1)
                }
                .safeAreaInset(edge: .bottom) {
                    // reserve space for custom tab bar + mini player
                    Color.clear.frame(height: musicManager.currentSong != nil ? miniPlayerHeight + tabBarHeight : tabBarHeight)
                }
                
                // gradient blur background - blocks touches and provides smooth fade
                VStack(spacing: 0) {
                    Spacer()
                    
                    // invisible touch blocker for the blur area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 180)
                        .contentShape(Rectangle())
                        .background(
                            Rectangle()
                                .fill(.thickMaterial)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.0),
                                            .init(color: .black.opacity(0.1), location: 0.15),
                                            .init(color: .black.opacity(0.4), location: 0.35),
                                            .init(color: .black.opacity(0.75), location: 0.55),
                                            .init(color: .black.opacity(0.95), location: 0.75),
                                            .init(color: .black, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
                .ignoresSafeArea(.keyboard)
                .ignoresSafeArea(.container, edges: .bottom)
                
                // bottom stack: mini player + tab bar
                VStack(spacing: 0) {
                    // mini player bar (only shows when a song is playing/paused)
                    if musicManager.currentSong != nil {
                        MiniPlayerBar(showNowPlaying: $showNowPlaying)
                            .padding(.horizontal, 8)
                    }
                    
                    // custom tab bar
                    CustomTabBar(selectedTab: $selectedTab)
                        .padding(.bottom, bottomSafeArea)
                }
                .contentShape(Rectangle())
                .ignoresSafeArea(.keyboard)
            }
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingModalView(isPresented: $showNowPlaying)
                .environmentObject(musicManager)
        }
        .onAppear {
            // hide the default tab bar
            UITabBar.appearance().isHidden = true
            
            if !musicManager.hasPermission {
                musicManager.checkPermission()
            }
        }
    }
}

// MARK: - Custom Tab Bar with Gradient Blur
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            TabBarButton(
                icon: "music.note.list",
                title: "Jukebox",
                isSelected: selectedTab == 0,
                action: { selectedTab = 0 }
            )
            
            TabBarButton(
                icon: "square.grid.2x2",
                title: "Collections",
                isSelected: selectedTab == 1,
                action: { selectedTab = 1 }
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .symbolVariant(isSelected ? .fill : .none)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Now Playing Modal View
struct NowPlayingModalView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Binding var isPresented: Bool
    
    @State private var volume: Double = 0.5
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var showQueue: Bool = false
    @State private var showLyrics: Bool = false
    @State private var gradientOpacity: Double = 1.0
    @State private var previousSongId: UInt64? = nil
    @State private var showFavoriteToast: Bool = false
    @State private var favoriteToastMessage: String = ""
    @State private var navigateToArtist: Bool = false
    @State private var navigateToAlbum: Bool = false
    
    // init with optional binding for backward compatibility
    init(isPresented: Binding<Bool>? = nil) {
        self._isPresented = isPresented ?? .constant(true)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // solid black background
                Color.black
                
                // gradient background from album artwork with fade transition
                nowPlayingBackground
                    .opacity(gradientOpacity)
                
                VStack(spacing: 0) {
                    Spacer().frame(height: 20)
                    
                    if let song = musicManager.currentSong {
                        nowPlayingContent(for: song, in: geometry)
                    } else {
                        noSongView
                    }
                }
                
                // favorite toast indicator
                if showFavoriteToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundColor(isFavorite ? .yellow : .white)
                            Text(favoriteToastMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView(isPresented: $showQueue)
                .environmentObject(musicManager)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView()
                .environmentObject(musicManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $navigateToArtist) {
            if let song = musicManager.currentSong {
                NavigationView {
                    ArtistDetailView(
                        artistName: song.artist ?? "Unknown Artist",
                        artistAlbums: getArtistAlbums(for: song.artist ?? "")
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") { navigateToArtist = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $navigateToAlbum) {
            if let song = musicManager.currentSong {
                NavigationView {
                    AlbumDetailView(album: getAlbumCollection(for: song))
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") { navigateToAlbum = false }
                            }
                        }
                }
                .environmentObject(musicManager)
            }
        }
        .onChange(of: musicManager.currentSong?.persistentID) { newId in
            // fade out and in when song changes
            if previousSongId != nil && newId != previousSongId {
                withAnimation(.easeOut(duration: 0.3)) {
                    gradientOpacity = 0.3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeIn(duration: 0.5)) {
                        gradientOpacity = 1.0
                    }
                }
            }
            previousSongId = newId
        }
        .onAppear {
            previousSongId = musicManager.currentSong?.persistentID
        }
    }
    
    // computed property for favorite status
    private var isFavorite: Bool {
        guard let songID = musicManager.currentSong?.persistentID else { return false }
        return favoritesManager.isFavorite(songID)
    }
    
    // helper to get artist albums
    private func getArtistAlbums(for artist: String) -> [MPMediaItemCollection] {
        let query = MPMediaQuery.albums()
        let predicate = MPMediaPropertyPredicate(value: artist, forProperty: MPMediaItemPropertyArtist)
        query.addFilterPredicate(predicate)
        return query.collections ?? []
    }
    
    // helper to get album collection for a song
    private func getAlbumCollection(for song: MPMediaItem) -> MPMediaItemCollection {
        let query = MPMediaQuery.albums()
        let predicate = MPMediaPropertyPredicate(value: song.albumPersistentID, forProperty: MPMediaItemPropertyAlbumPersistentID)
        query.addFilterPredicate(predicate)
        return query.collections?.first ?? MPMediaItemCollection(items: [song])
    }
    
    // MARK: - Background
    private var nowPlayingBackground: some View {
        Group {
            if let song = musicManager.currentSong, let artwork = song.artwork {
                let imageSize = CGSize(width: 400, height: 400)
                if let image = artwork.image(at: imageSize) {
                    AlbumFluidGradient(image: image, isAnimating: true)
                } else {
                    FluidGradientView(colors: [.purple, .blue, .pink, .orange], speed: 0.3, isAnimating: true)
                }
            } else {
                FluidGradientView(colors: [.gray, .brown, .black], speed: 0.2, isAnimating: true)
            }
        }
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private func nowPlayingContent(for song: MPMediaItem, in geometry: GeometryProxy) -> some View {
        Group {
            Spacer().frame(height: 60)
            
            // album artwork
            if let artwork = song.artwork {
                let artworkSize = CGSize(width: 400, height: 400)
                if let image = artwork.image(at: artworkSize) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 380)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        .padding(.horizontal, 30)
                        .scaleEffect(musicManager.isPlaying ? 1 : 0.95)
                        .animation(.spring(), value: musicManager.isPlaying)
                } else {
                    placeholderArtwork
                }
            } else {
                placeholderArtwork
            }
            
            Spacer().frame(height: 24)
        }
        
        // song info
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title ?? "Unknown Title")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Menu {
                    Button(action: { navigateToArtist = true }) {
                        Label("Go to Artist", systemImage: "person.fill")
                    }
                    Button(action: { navigateToAlbum = true }) {
                        Label("Go to \(song.albumTitle ?? "Album")", systemImage: "music.note.list")
                    }
                } label: {
                    Text(song.artist ?? "Unknown Artist")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: { 
                if let songID = musicManager.currentSong?.persistentID {
                    let wasAlreadyFavorite = favoritesManager.isFavorite(songID)
                    favoritesManager.toggleFavorite(songID)
                    
                    // show toast
                    favoriteToastMessage = wasAlreadyFavorite ? "Removed from Favourites" : "Added to Favourites"
                    withAnimation(.spring()) {
                        showFavoriteToast = true
                    }
                    
                    // hide toast after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut) {
                            showFavoriteToast = false
                        }
                    }
                }
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 22))
                    .foregroundColor(isFavorite ? .yellow : .white.opacity(0.7))
            }
        }
        .padding(.horizontal, 30)
        
        Spacer().frame(height: 24)
        
        // progress
        VStack(spacing: 8) {
            CustomProgressSlider(
                currentTime: musicManager.currentTime,
                duration: musicManager.duration,
                onSeek: { musicManager.seek(to: $0) }
            )
            .padding(.horizontal, 30)
            
            HStack {
                Text(formatTime(musicManager.currentTime))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 45, alignment: .leading)
                
                Spacer()
                
                // bit rate badge - centered and fixed position
                if let quality = musicManager.audioQuality {
                    HStack(spacing: 4) {
                        Image(systemName: quality.iconName)
                            .font(.system(size: 10))
                        Text(quality.badgeText)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                Text("-" + formatTime(musicManager.duration - musicManager.currentTime))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 45, alignment: .trailing)
            }
            .padding(.horizontal, 30)
        }
        
        Spacer().frame(height: 40)
        
        // playback controls - moved lower
        HStack(spacing: 50) {
            Button(action: { musicManager.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            
            Button(action: { musicManager.togglePlayPause() }) {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.white)
            }
            
            Button(action: { musicManager.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
        
        Spacer()
        
        // bottom controls
        HStack(spacing: 0) {
            Spacer()
            
            Button(action: { showLyrics = true }) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            AirPlayButton(tintColor: UIColor.white.withAlphaComponent(0.7))
                .frame(width: 24, height: 24)
            
            Spacer()
            
            // queue button - opens queue view
            Button(action: { 
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    showQueue = true 
                }
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.bottom, 34)
    }
    
    // MARK: - No Song View
    private var noSongView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.5))
            
            Text("No Song Playing")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Select a song from the Jukebox to start playing")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
    
    // MARK: - Placeholder
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .frame(height: 380)
            
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 30)
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Mini Player Bar
struct MiniPlayerBar: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Binding var showNowPlaying: Bool
    
    var body: some View {
        Button(action: { showNowPlaying = true }) {
            HStack(spacing: 12) {
                // album artwork
                if let song = musicManager.currentSong, let artwork = song.artwork {
                    let size = CGSize(width: 48, height: 48)
                    if let image = artwork.image(at: size) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .cornerRadius(6)
                    } else {
                        placeholderArt
                    }
                } else {
                    placeholderArt
                }
                
                // song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.currentSong?.title ?? "Not Playing")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(musicManager.currentSong?.artist ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // play/pause button
                Button(action: { musicManager.togglePlayPause() }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.primary)
                }
                .padding(.trailing, 4)
                
                // next button
                Button(action: { musicManager.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
    
    private var placeholderArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 48, height: 48)
            
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.gray)
        }
    }
}
