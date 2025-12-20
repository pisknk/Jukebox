//
//  NowPlayingView.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import SwiftUI
import MediaPlayer

struct NowPlayingView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Binding var isPresented: Bool
    @State private var volume: Double = 0.5
    @State private var isFavorite: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var showLyrics: Bool = false
    
    // init with optional binding for backward compatibility
    init(isPresented: Binding<Bool>? = nil) {
        self._isPresented = isPresented ?? .constant(true)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // solid black background to prevent white showing through
                Color.black
                    .ignoresSafeArea()
                
                // blurred background from album artwork
                backgroundView
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // drag indicator
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                    
                    if let song = musicManager.currentSong {
                        Group {
                            Spacer().frame(height: 60)
                            artworkView(for: song)
                            Spacer().frame(height: 40)
                            songInfoView(for: song)
                            Spacer().frame(height: 24)
                        }
                        
                        Group {
                            progressView
                            Spacer().frame(height: 32)
                            playbackControls
                        }
                        
                        Group {
                            Spacer()
                            bottomControls
                            Spacer().frame(height: 50)
                        }
                    } else {
                        noSongView
                    }
                }
            }
            .offset(y: dragOffset)
            .opacity(opacity)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                            // fade out as user drags down
                            opacity = max(0.5, 1.0 - (value.translation.height / 500))
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 150 || value.predictedEndTranslation.height > 300 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                opacity = 0
                                dragOffset = geometry.size.height
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                isPresented = false
                            }
                        } else {
                            withAnimation(.spring()) {
                                dragOffset = 0
                                opacity = 1.0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showLyrics) {
            LyricsView()
                .environmentObject(musicManager)
        }
    }
    
    // MARK: - Background
    private var backgroundView: some View {
        Group {
            if let song = musicManager.currentSong, let artwork = song.artwork {
                let imageSize = CGSize(width: 400, height: 400)
                if let image = artwork.image(at: imageSize) {
                    AlbumFluidGradient(image: image)
                } else {
                    FluidGradientView(colors: [.purple, .blue, .pink, .orange], speed: 0.3)
                        .ignoresSafeArea()
                }
            } else {
                FluidGradientView(colors: [.gray, .brown, .black], speed: 0.2)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Artwork
    @ViewBuilder
    private func artworkView(for song: MPMediaItem) -> some View {
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
    }
    
    // MARK: - Song Info
    private func songInfoView(for song: MPMediaItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title ?? "Unknown Title")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(song.artist ?? "Unknown Artist")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: { 
                withAnimation(.spring()) {
                    isFavorite.toggle() 
                }
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 22))
                    .foregroundColor(isFavorite ? .yellow : .white.opacity(0.7))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 30)
    }
    
    // MARK: - Progress
    private var progressView: some View {
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
                
                Spacer()
                
                Text(formatTime(musicManager.duration))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 30)
        }
    }
    
    // MARK: - Playback Controls
    private var playbackControls: some View {
        HStack(spacing: 50) {
            Button(action: { musicManager.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            
            Button(action: { musicManager.togglePlayPause() }) {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.white)
            }
            
            Button(action: { musicManager.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 40)
    }
    
    // MARK: - Volume
    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            
            CustomVolumeSlider(volume: $volume)
            
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 30)
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button(action: { showLyrics = true }) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
    }
    
    // MARK: - No Song View
    private var noSongView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.5))
            
            Text("No Song Playing")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Select a song from the Library to start playing")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
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

// MARK: - Custom Progress Slider
struct CustomProgressSlider: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var dragging = false
    @State private var captured: Double? = nil
    @State private var displayed: Double? = nil
    
    private var percentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var body: some View {
        GeometryReader { geometry in
            let displayedPercentage = displayed ?? percentage
            let width = geometry.size.width * min(1, max(0, CGFloat(displayedPercentage)))
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .saturation(1.6)
                
                Rectangle()
                    .fill(.white)
                    .frame(width: width)
                    .opacity(dragging ? 0.8 : 0.4)
                    .animation(.easeInOut, value: dragging)
                    .animation(.linear(duration: 0.1), value: width)
            }
            .cornerRadius(8)
            .highPriorityGesture(DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
                .onChanged { gesture in
                    dragging = true
                    
                    if captured == nil {
                        captured = percentage
                    }
                    
                    let dragWidth = geometry.size.width
                    let offset = min(dragWidth, max(-dragWidth, gesture.translation.width))
                    let moved: Double = Double(offset / dragWidth)
                    let acceleration: Double = 0.8
                    let modifier = moved * acceleration
                    
                    displayed = max(0, min(1, captured! + modifier))
                }
                .onEnded { _ in
                    dragging = false
                    
                    if let displayed = displayed {
                        onSeek(duration * displayed)
                    }
                    
                    displayed = nil
                    captured = nil
                }
            )
        }
        .frame(height: dragging ? 12 : 8)
        .shadow(color: .black.opacity(0.2), radius: dragging ? 10 : 0)
        .animation(.spring(), value: dragging)
    }
}

// MARK: - Custom Volume Slider
struct CustomVolumeSlider: View {
    @Binding var volume: Double
    @State private var dragging = false
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(1, max(0, CGFloat(volume)))
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.4))
                
                Rectangle()
                    .fill(.white)
                    .frame(width: width)
                    .opacity(0.8)
            }
            .cornerRadius(4)
            .gesture(DragGesture(minimumDistance: 0.0)
                .onChanged { gesture in
                    dragging = true
                    let newVolume = min(1, max(0, Double(gesture.location.x / geometry.size.width)))
                    volume = newVolume
                }
                .onEnded { _ in
                    dragging = false
                }
            )
        }
        .frame(height: 4)
    }
}
