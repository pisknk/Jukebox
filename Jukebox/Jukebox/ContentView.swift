//
//  ContentView.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import SwiftUI
import MediaPlayer

struct ContentView: View {
    var body: some View {
        // the design is fixed for the whole launch (see AppDesign)
        if #available(iOS 26, *), AppDesign.isNativeGlass {
            NativeGlassRootView()
        } else {
            AmityRootView()
        }
    }
}

// MARK: - Amity 1.0 (custom chrome)
struct AmityRootView: View {
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
            
            // the search tab only exists in Native Glass
            if selectedTab > 1 { selectedTab = 0 }
            
            if !musicManager.hasPermission && MPMediaLibrary.authorizationStatus() == .notDetermined {
                musicManager.checkPermission()
            }
        }
    }
}

// MARK: - Native Glass (iOS 26 system chrome)
@available(iOS 26, *)
struct NativeGlassRootView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var showNowPlaying = false
    @AppStorage("selectedTab") private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Jukebox", systemImage: "music.note.list", value: 0) {
                LibraryView()
            }
            Tab("Collections", systemImage: "square.grid.2x2", value: 1) {
                CollectionsView()
            }
            // the round search button beside the tab bar; the field opens at the bottom
            Tab(value: 2, role: .search) {
                LibrarySearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NativeMiniPlayer(showNowPlaying: $showNowPlaying)
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingModalView(isPresented: $showNowPlaying)
                .environmentObject(musicManager)
        }
        .onAppear {
            if !musicManager.hasPermission && MPMediaLibrary.authorizationStatus() == .notDetermined {
                musicManager.checkPermission()
            }
        }
    }
}

/// the mini player in the tab bar's accessory slot (like the Music app)
@available(iOS 26, *)
struct NativeMiniPlayer: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Binding var showNowPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image = musicManager.currentArtwork {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.currentSong?.title ?? "Not Playing")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if let artist = musicManager.currentSong?.artist {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: { musicManager.togglePlayPause() }) {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(musicManager.currentSong == nil)

            Button(action: { musicManager.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(musicManager.currentSong == nil)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if musicManager.currentSong != nil {
                showNowPlaying = true
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
    
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var showQueue: Bool = false
    @State private var showLyrics: Bool = false
    @State private var gradientOpacity: Double = 1.0
    @State private var previousSongId: UInt64? = nil
    @State private var showFavoriteToast: Bool = false
    @State private var favoriteToastMessage: String = ""
    @State private var toastID = 0
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
                    ArtistDetailView(artistName: song.artist ?? "Unknown Artist")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") { navigateToArtist = false }
                        }
                    }
                }
                .environmentObject(musicManager)
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
    
    // helper to get album collection for a song
    private func getAlbumCollection(for song: MPMediaItem) -> MPMediaItemCollection {
        LibraryQueries.album(containing: song) ?? MPMediaItemCollection(items: [song])
    }
    
    // MARK: - Background
    private var nowPlayingBackground: some View {
        Group {
            if #available(iOS 26, *), AppDesign.isNativeGlass {
                // native MeshGradient + CIKMeans colours (iOS 13 lyrics style)
                AlbumMeshBackground(
                    image: musicManager.currentArtwork,
                    imageID: musicManager.currentSong?.persistentID,
                    isAnimating: musicManager.isPlaying
                )
            } else if let song = musicManager.currentSong, let image = musicManager.currentArtwork {
                AlbumFluidGradient(image: image, imageID: song.persistentID, isAnimating: musicManager.isPlaying)
            } else if musicManager.currentSong != nil {
                FluidGradientView(colors: [.purple, .blue, .pink, .orange], speed: 0.3, isAnimating: musicManager.isPlaying)
            } else {
                FluidGradientView(colors: [.gray, .brown, .black], speed: 0.2, isAnimating: false)
            }
        }
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private func nowPlayingContent(for song: MPMediaItem, in geometry: GeometryProxy) -> some View {
        Group {
            Spacer().frame(height: 60)
            
            // album artwork
            if let image = musicManager.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 380)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, 30)
                    .scaleEffect(musicManager.isPlaying ? 1 : 0.95)
                    .animation(.spring(), value: musicManager.isPlaying)
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
                    
                    // hide toast after delay (unless a newer toast replaced it)
                    toastID += 1
                    let currentToast = toastID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard currentToast == toastID else { return }
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
        
        // progress (its own view, so only it redraws as the song plays)
        NowPlayingProgressSection(
            progress: musicManager.progress,
            quality: musicManager.audioQuality,
            onSeek: { musicManager.seek(to: $0) }
        )
        
        Spacer().frame(height: 40)
        
        // playback controls - moved lower
        HStack(spacing: AppDesign.isNativeGlass ? 28 : 50) {
            Button(action: { musicManager.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: AppDesign.isNativeGlass ? 64 : nil, height: AppDesign.isNativeGlass ? 64 : nil)
                    .adaptiveGlass(in: Circle())
            }
            
            Button(action: { musicManager.togglePlayPause() }) {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: AppDesign.isNativeGlass ? 40 : 56))
                    .foregroundColor(.white)
                    .frame(width: AppDesign.isNativeGlass ? 88 : nil, height: AppDesign.isNativeGlass ? 88 : nil)
                    .adaptiveGlass(in: Circle())
            }
            
            Button(action: { musicManager.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: AppDesign.isNativeGlass ? 64 : nil, height: AppDesign.isNativeGlass ? 64 : nil)
                    .adaptiveGlass(in: Circle())
            }
        }
        .modifier(NativeGlassPlainButtons())
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
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 380)
            
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 30)
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
    
}

/// plain buttons so the glass circles aren't tinted; Amity keeps the default style
private struct NativeGlassPlainButtons: ViewModifier {
    func body(content: Content) -> some View {
        if AppDesign.isNativeGlass {
            content.buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Now Playing Progress
struct NowPlayingProgressSection: View {
    @ObservedObject var progress: PlaybackProgress
    let quality: MusicPlayerManager.AudioQuality?
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 8) {
            CustomProgressSlider(
                currentTime: progress.currentTime,
                duration: progress.duration,
                onSeek: onSeek
            )
            .padding(.horizontal, 30)

            HStack {
                Text(formatTime(progress.currentTime))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
                    .frame(width: 45, alignment: .leading)

                Spacer()

                // bit rate badge - centered and fixed position
                if let quality = quality {
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

                Text("-" + formatTime(max(0, progress.duration - progress.currentTime)))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
                    .frame(width: 45, alignment: .trailing)
            }
            .padding(.horizontal, 30)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
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
                if let image = musicManager.currentArtwork {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .cornerRadius(6)
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
