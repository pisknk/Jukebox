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
    /// .inline when the tab bar has shrunk and the player sits beside it; .expanded above it
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// the narrow spot next to the collapsed tab bar: drop the skip button so the title fits
    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: isInline ? 8 : 10) {
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
            .frame(width: isInline ? 28 : 32, height: isInline ? 28 : 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // long titles scroll to show the whole thing
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    text: musicManager.currentSong?.title ?? "Not Playing",
                    font: .system(size: 14, weight: .medium)
                )
                if let artist = musicManager.currentSong?.artist {
                    MarqueeText(
                        text: artist,
                        font: .system(size: 12),
                        color: .secondary
                    )
                }
            }

            Spacer(minLength: isInline ? 4 : 8)

            Button(action: { musicManager.togglePlayPause() }) {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(musicManager.currentSong == nil)

            if !isInline {
                Button(action: { musicManager.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(musicManager.currentSong == nil)
            }
        }
        .padding(.horizontal, isInline ? 8 : 12)
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
    @ObservedObject private var motion = MotionArtworkManager.shared
    
    /// Native Glass: the song's animated album cover, shown full-width at the top
    private var fullBleedVideo: URL? {
        AppDesign.isNativeGlass ? motion.currentVideo : nil
    }
    
    // init with optional binding for backward compatibility
    init(isPresented: Binding<Bool>? = nil) {
        self._isPresented = isPresented ?? .constant(true)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // solid black background
                Color.black
                
                if let video = fullBleedVideo {
                    // the cover's own bottom-edge colour continues down the screen
                    fullBleedBackground
                        .transition(.opacity)
                    
                    // animated album cover across the top, fading into that colour
                    VStack(spacing: 0) {
                        FullBleedMotionCover(
                            video: video,
                            poster: motion.currentPoster ?? musicManager.currentArtwork,
                            isPlaying: musicManager.isPlaying
                        )
                        .frame(width: geometry.size.width, height: fullBleedCoverHeight(in: geometry))
                        .id(video)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                } else {
                    // gradient background from album artwork with fade transition
                    nowPlayingBackground
                        .opacity(gradientOpacity)
                }
                
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
        .animation(.easeInOut(duration: 0.6), value: fullBleedVideo)
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
            if let song = musicManager.currentSong, let image = musicManager.currentArtwork {
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
        if fullBleedVideo != nil {
            // the animated cover fills the top; the song info sits over its faded bottom
            Spacer().frame(height: fullBleedInfoOffset(in: geometry))
        } else {
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
                    .transition(.scale(scale: 1.18).combined(with: .opacity))
            } else {
                placeholderArtwork
            }
            
            Spacer().frame(height: 24)
        }
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
        
        // system volume, like the Music app (fills the space under the full-width cover)
        if fullBleedVideo != nil {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                SystemVolumeSlider()
                    .frame(height: 34)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 30)
        }
        
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
    
    /// where the song info starts under a full-width animated cover: over the cover's faded
    /// bottom, but never so low that the controls run off a small screen
    private func fullBleedInfoOffset(in geometry: GeometryProxy) -> CGFloat {
        let coverOverlap = fullBleedCoverHeight(in: geometry) * 0.8
        let fitsControls = geometry.size.height - 450
        return max(60, min(coverOverlap, fitsControls))
    }
    
    /// the full-width cover takes the top 68% of the screen (as in twenty-one-reborn)
    private func fullBleedCoverHeight(in geometry: GeometryProxy) -> CGFloat {
        geometry.size.height * 0.68
    }
    
    /// solid cover-edge colour, a little darker towards the bottom
    private var fullBleedBackground: some View {
        Color(uiColor: motion.currentEdgeColor ?? UIColor(white: 0.12, alpha: 1))
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            )
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

// MARK: - Full-bleed Motion Cover
/// static -> animated: the video's first frame shows full-width right away, and the
/// video fades in on top once it can display (as in twenty-one-reborn)
struct FullBleedMotionCover: View {
    let video: URL
    let poster: UIImage?
    let isPlaying: Bool

    @State private var videoReady = false

    var body: some View {
        ZStack {
            if let poster = poster {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            LoopingVideoView(url: video, isPlaying: isPlaying) {
                withAnimation(.easeOut(duration: 0.2)) { videoReady = true }
            }
            .opacity(videoReady ? 1 : 0)
        }
        .clipped()
        // solid down to 72%, half by 90%, gone at the bottom
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0.5), location: 0.9),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
    }
}

/// the system volume slider (MPVolumeView), tinted for the dark Now Playing screen
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
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
