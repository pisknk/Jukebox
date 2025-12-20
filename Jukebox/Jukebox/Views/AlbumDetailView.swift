//
//  AlbumDetailView.swift
//  Jukebox
//
//  Detail view for an album showing artwork, info, and track list.
//

import SwiftUI
import MediaPlayer

struct AlbumDetailView: View {
    let album: MPMediaItemCollection
    @EnvironmentObject var musicManager: MusicPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var shadowColor: Color = .black.opacity(0.3)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // album artwork
                if let artwork = album.representativeItem?.artwork,
                   let image = artwork.image(at: CGSize(width: 300, height: 300)) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 260, height: 260)
                        .cornerRadius(8)
                        .shadow(color: shadowColor, radius: 25, x: 0, y: 10)
                        .onAppear {
                            // Extract color for shadow
                            DispatchQueue.global(qos: .userInteractive).async {
                                let colors = image.extractDominantColors(count: 1)
                                if let first = colors.first {
                                    DispatchQueue.main.async {
                                        withAnimation(.easeOut(duration: 0.5)) {
                                            self.shadowColor = first.opacity(0.6)
                                        }
                                    }
                                }
                            }
                        }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 260, height: 260)
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                    }
                }
                
                // album info
                VStack(spacing: 6) {
                    Text(album.representativeItem?.albumTitle ?? "Unknown Album")
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text(album.representativeItem?.artist ?? "Unknown Artist")
                        .font(.system(size: 18))
                        .foregroundColor(.pink)
                    
                    if let year = album.representativeItem?.value(forProperty: "year") as? Int, year > 0 {
                        Text(String(year))
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                // play / shuffle buttons
                HStack(spacing: 16) {
                    Button(action: {
                        if let first = album.items.first {
                            let title = album.representativeItem?.albumTitle ?? "Album"
                            musicManager.play(songs: album.items, startWith: first, context: title)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pink.opacity(0.15))
                        .foregroundColor(.pink)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        if !musicManager.shuffleEnabled {
                            musicManager.toggleShuffle()
                        }
                        if let random = album.items.randomElement() {
                            let title = album.representativeItem?.albumTitle ?? "Album"
                            musicManager.play(songs: album.items, startWith: random, context: title)
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pink.opacity(0.15))
                        .foregroundColor(.pink)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                
                // track list
                VStack(spacing: 0) {
                    ForEach(Array(album.items.enumerated()), id: \.element.persistentID) { index, song in
                        Button(action: {
                            let title = album.representativeItem?.albumTitle ?? "Album"
                            musicManager.play(songs: album.items, startWith: song, context: title)
                        }) {
                            HStack(spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                                
                                Text(song.title ?? "Unknown")
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Button(action: {
                                    // show add to playlist or menu
                                }) {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        
                        if index < album.items.count - 1 {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.top, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
