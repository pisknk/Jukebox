//
//  LyricsView.swift
//  Jukebox
//
//  lyrics view optimized for portrait orientation
//

import SwiftUI
import MediaPlayer

struct LyricsView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Environment(\.dismiss) var dismiss
    
    @State private var lyrics: [LyricLine] = []
    @State private var isLoading = true
    @State private var currentIndex: Int = -1  // -1 = before the first line
    @State private var loadedSongID: UInt64? = nil
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var isUserScrolling = false
    @State private var scrollTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // drag indicator
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            
            // header
            header
            
            // content
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadLyrics)
        .onDisappear {
            scrollTimer?.invalidate()
            scrollTimer = nil
        }
        .onReceive(musicManager.progress.$currentTime, perform: updateCurrentLine)
        .onChange(of: musicManager.currentSong?.persistentID) { _ in
            loadLyrics()
        }
    }
    
    // computed property for favorite status
    private var isFavorite: Bool {
        guard let songID = musicManager.currentSong?.persistentID else { return false }
        return favoritesManager.isFavorite(songID)
    }
    
    // MARK: - Background
    
    private var background: some View {
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
            } else {
                FluidGradientView(colors: [.purple, .blue, .pink, .orange], speed: 0.3, isAnimating: musicManager.isPlaying)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            // album art
            Group {
                if let image = musicManager.currentArtwork {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                }
            }
            .frame(width: 52, height: 52)
            .cornerRadius(6)
            
            // song info
            VStack(alignment: .leading, spacing: 2) {
                Text(musicManager.currentSong?.title ?? "Unknown")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(musicManager.currentSong?.artist ?? "Unknown Artist")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // favorite button
            Button(action: {
                if let songID = musicManager.currentSong?.persistentID {
                    favoritesManager.toggleFavorite(songID)
                }
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 20))
                    .foregroundColor(isFavorite ? .yellow : .white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().tint(.white).scaleEffect(1.2)
                Spacer()
            }
        } else if lyrics.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "text.bubble")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.4))
                Text("No Lyrics Available")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
        } else {
            lyricsScroll
        }
    }
    
    // MARK: - Lyrics Scroll
    
    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(lyrics.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 8) {
                            // main lyric line
                            // current line: show without parenthetical (it's shown as subtitle)
                            // other lines: strip parenthetical completely (only show when it's their turn)
                            Text(line.isInstrumental ? "♪" : stripParenthetical(line.text))
                                .font(.system(
                                    size: index == currentIndex ? 32 : 30,
                                    weight: .bold
                                ))
                                .foregroundColor(.white)
                                .opacity(opacityFor(index))
                                .blur(radius: blurFor(index))
                                .scaleEffect(index == currentIndex ? 1.02 : 1.0)
                                .offset(y: index == currentIndex ? 0 : 0)
                                .fixedSize(horizontal: false, vertical: true)
                                // bouncy spring animation when lyric becomes current
                                .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0.2), value: currentIndex)
                                .animation(.easeInOut(duration: 0.3), value: isUserScrolling)
                            
                            // parenthetical subtitle (show CURRENT line's own parenthetical)
                            if index == currentIndex, let subtitle = extractParenthetical(from: line.text) {
                                Text(subtitle)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 60)
                        .id(index)
                        // animate all lines as they change position
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                        .onTapGesture {
                            seekToLine(index)
                        }
                    }
                    Spacer().frame(height: 300)
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10).onChanged { _ in
                    // user started scrolling
                    if !isUserScrolling {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isUserScrolling = true
                        }
                    }
                    
                    // reset timer
                    scrollTimer?.invalidate()
                    scrollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        scrollTimer = nil
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isUserScrolling = false
                        }
                    }
                }
            )
            .onAppear {
                // jump straight to the current line when lyrics appear mid-song
                if currentIndex >= 0 {
                    proxy.scrollTo(currentIndex, anchor: .top)
                }
            }
            .onChange(of: currentIndex) { idx in
                if !isUserScrolling && idx >= 0 {
                    // smooth spring animation for scroll movement
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        proxy.scrollTo(idx, anchor: .top)
                    }
                }
            }
        }
    }
    
    // MARK: - Parenthetical Helpers
    
    /// extract text inside () from a string
    private func extractParenthetical(from text: String) -> String? {
        guard let openParen = text.firstIndex(of: "("),
              let closeParen = text.firstIndex(of: ")"),
              openParen < closeParen else { return nil }
        
        let start = text.index(after: openParen)
        let content = String(text[start..<closeParen]).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }
    
    /// remove parenthetical text from a string for cleaner display
    private func stripParenthetical(_ text: String) -> String {
        // remove (content) pattern but keep the rest
        guard let openParen = text.firstIndex(of: "("),
              let closeParen = text.firstIndex(of: ")"),
              openParen < closeParen else { return text }
        
        var result = text
        let rangeToRemove = openParen...closeParen
        result.removeSubrange(rangeToRemove)
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Helpers
    
    private func opacityFor(_ index: Int) -> Double {
        let dist = index - currentIndex
        if dist == 0 { return 1.0 }
        
        // when user is scrolling, show all lyrics more clearly
        if isUserScrolling {
            if dist < 0 { return 0.5 }
            return 0.6
        }
        
        // normal gradient effect
        if dist < 0 { return max(0.25, 0.5 + Double(dist) * 0.1) }
        switch dist {
        case 1: return 0.55
        case 2: return 0.4
        case 3: return 0.3
        case 4: return 0.2
        default: return 0.15
        }
    }
    
    private func blurFor(_ index: Int) -> CGFloat {
        let dist = index - currentIndex
        
        // previous line and current line: no blur
        if dist <= 0 { return 0 }
        
        // when user is scrolling, reduce blur to show lyrics clearly
        if isUserScrolling {
            return 0
        }
        
        // intensified blur for upcoming lyrics
        switch dist {
        case 1: return 0.8
        case 2: return 1.5
        case 3: return 2.5
        case 4: return 3.5
        case 5: return 4.5
        default: return 5.5
        }
    }
    
    private func seekToLine(_ index: Int) {
        guard index < lyrics.count else { return }
        let line = lyrics[index]
        musicManager.seek(to: line.time)
        currentIndex = index
    }
    
    private func loadLyrics() {
        lyrics = []
        currentIndex = -1
        loadedSongID = musicManager.currentSong?.persistentID

        guard let song = musicManager.currentSong,
              let title = song.title,
              let artist = song.artist else {
            isLoading = false
            return
        }

        isLoading = true
        let requestedID = song.persistentID

        LyricsManager.shared.getLyrics(track: title, artist: artist) { result in
            // the song changed while we were waiting: these lyrics belong to the old one
            guard requestedID == loadedSongID else { return }
            isLoading = false
            if let result = result, !result.isEmpty {
                lyrics = result
                updateCurrentLine(time: musicManager.currentTime)
            }
        }
    }

    private func updateCurrentLine(time: TimeInterval) {
        guard !lyrics.isEmpty else { return }
        let idx = LyricsManager.shared.currentLineIndex(for: time, in: lyrics) ?? -1
        if idx != currentIndex {
            currentIndex = idx
        }
    }
}
