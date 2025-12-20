//
//  QueueView.swift
//  Jukebox
//
//  Queue view showing playback controls and upcoming songs.
//

import SwiftUI
import MediaPlayer

struct QueueView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Binding var isPresented: Bool
    @ObservedObject var sleepTimer = SleepTimerManager.shared
    
    var body: some View {
        ZStack {
            // translucent blur background
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer().frame(height: 20)
                
                // sleep timer indicator
                if sleepTimer.isActive {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.purple)
                        
                        Text(sleepTimer.shortDescription)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { sleepTimer.stopTimer() }) {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                
                // control buttons
                HStack(spacing: 16) {
                    // shuffle button
                    Button(action: { musicManager.toggleShuffle() }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(musicManager.shuffleEnabled ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(musicManager.shuffleEnabled ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    // repeat button
                    Button(action: { musicManager.cycleRepeatMode() }) {
                        Image(systemName: musicManager.repeatMode.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(musicManager.repeatMode != .off ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(musicManager.repeatMode != .off ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    // autoplay button
                    Button(action: { musicManager.toggleAutoplay() }) {
                        Image(systemName: "infinity")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(musicManager.autoplayEnabled ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(musicManager.autoplayEnabled ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                
                // section header
                HStack {
                    Text(musicManager.playbackContextTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                
                // queue list with reordering
                List {
                    ForEach(Array(upcomingSongs.enumerated()), id: \.element.persistentID) { index, song in
                        QueueSongRow(song: song, index: index)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // play this song from the queue
                                playQueueSongAtIndex(index)
                            }
                    }
                    .onMove(perform: moveItems)
                    .onDelete(perform: deleteItems)
                    
                    // "Continue Playing" / Autoplay indicator
                    if musicManager.autoplayEnabled {
                        Section {
                            ForEach(Array(musicManager.autoplayQueue.enumerated()), id: \.element.persistentID) { index, song in
                                QueueSongRow(song: song, index: index)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Image(systemName: "infinity")
                                Text("Continue Playing")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 8)
                            .textCase(nil) // preserve case
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
                
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // get ALL songs after current
    private var upcomingSongs: [MPMediaItem] {
        guard let currentIndex = musicManager.currentIndex,
              !musicManager.currentPlaylist.isEmpty else {
            return []
        }
        
        let startIndex = currentIndex + 1
        if startIndex < musicManager.currentPlaylist.count {
            return Array(musicManager.currentPlaylist[startIndex...])
        }
        return []
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        musicManager.moveQueueItem(from: source, to: destination)
    }
    
    private func deleteItems(at offsets: IndexSet) {
        // calculate actual indices in playlist
        guard let currentIndex = musicManager.currentIndex else { return }
        let actualIndices = offsets.map { $0 + currentIndex + 1 }
        for index in actualIndices.sorted().reversed() {
            musicManager.removeFromQueue(at: index)
        }
    }
    
    private func playQueueSongAtIndex(_ queueIndex: Int) {
        // calculate actual index in playlist (queueIndex is offset from current)
        guard let currentIndex = musicManager.currentIndex else { return }
        let actualIndex = currentIndex + 1 + queueIndex
        musicManager.playFromQueueAtIndex(actualIndex)
    }
}

// MARK: - Queue Song Row
struct QueueSongRow: View {
    let song: MPMediaItem
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // album artwork
            if let artwork = song.artwork {
                let size = CGSize(width: 56, height: 56)
                if let image = artwork.image(at: size) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .cornerRadius(6)
                } else {
                    placeholderArt
                }
            } else {
                placeholderArt
            }
            
            // song info
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title ?? "Unknown Title")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(song.artist ?? "Unknown Artist")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
        }
    }
    
    private var placeholderArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
            
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.gray)
        }
    }
}
