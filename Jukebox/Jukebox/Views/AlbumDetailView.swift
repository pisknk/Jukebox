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
    @State private var songForPlaylist: MPMediaItem?

    private var albumTitle: String {
        album.representativeItem?.albumTitle ?? "Album"
    }

    /// release year, if the album has one
    private var releaseYear: Int? {
        if let date = album.representativeItem?.releaseDate {
            return Calendar.current.component(.year, from: date)
        }
        if let year = album.representativeItem?.value(forProperty: "year") as? Int, year > 0 {
            return year
        }
        return nil
    }
    
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
                    
                    if let year = releaseYear {
                        Text(String(year))
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                // play / shuffle buttons
                HStack(spacing: 16) {
                    Button(action: {
                        musicManager.playInOrder(songs: album.items, context: albumTitle)
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
                        musicManager.playShuffled(songs: album.items, context: albumTitle)
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
                        HStack(spacing: 0) {
                            Button(action: {
                                musicManager.play(songs: album.items, startWith: song, context: albumTitle)
                            }) {
                                HStack(spacing: 16) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24)
                                    
                                    Text(song.title ?? "Unknown")
                                        .font(.system(size: 17))
                                        .foregroundColor(song.assetURL == nil ? .secondary : .primary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                                .padding(.leading, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Menu {
                                Button {
                                    musicManager.addToQueue(song: song)
                                } label: {
                                    Label("Add to Queue", systemImage: "text.badge.plus")
                                }
                                Button {
                                    songForPlaylist = song
                                } label: {
                                    Label("Add to Playlist", systemImage: "music.note.list")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .padding(.trailing, 8)
                        }
                        
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
        .sheet(item: $songForPlaylist) { song in
            AddToPlaylistView(song: song)
        }
    }
}
