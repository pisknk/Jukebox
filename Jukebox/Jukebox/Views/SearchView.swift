//
//  SearchView.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import SwiftUI
import MediaPlayer

struct SearchView: View {
    @EnvironmentObject var musicManager: MusicPlayerManager
    @State private var searchText = ""
    
    var filteredSongs: [MPMediaItem] {
        if searchText.isEmpty {
            return []
        } else {
            return musicManager.songs.filter { song in
                let title = song.title?.lowercased() ?? ""
                let artist = song.artist?.lowercased() ?? ""
                let album = song.albumTitle?.lowercased() ?? ""
                let query = searchText.lowercased()
                
                return title.contains(query) || artist.contains(query) || album.contains(query)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // search bar
                SearchBar(text: $searchText, placeholder: "Songs, Artists, Albums")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                if musicManager.hasPermission {
                    if searchText.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            
                            Text("Search Your Music")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Enter a song, artist, or album name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredSongs.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.slash")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            
                            Text("No Results")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Try a different search term")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredSongs, id: \.persistentID) { song in
                            SongRow(song: song)
                                .onTapGesture {
                                    musicManager.play(song: song)
                                }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No Permission")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Please grant permission to access your music library in Settings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Search")
        }
    }
}
