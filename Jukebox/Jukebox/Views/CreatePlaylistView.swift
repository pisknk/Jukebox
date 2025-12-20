//
//  CreatePlaylistView.swift
//  Jukebox
//
//  View for creating a new custom playlist.
//

import SwiftUI
import MediaPlayer

struct CreatePlaylistView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var playlistManager = PlaylistManager.shared
    
    @State private var playlistName: String = ""
    @FocusState private var isNameFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // playlist icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [.pink.opacity(0.4), .purple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
                .padding(.top, 40)
                
                // name field
                TextField("Playlist Name", text: $playlistName)
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)
                    .focused($isNameFocused)
                
                Spacer()
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if !playlistName.trimmingCharacters(in: .whitespaces).isEmpty {
                            _ = playlistManager.createPlaylist(name: playlistName.trimmingCharacters(in: .whitespaces))
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
    }
}

// MARK: - Add To Playlist View
struct AddToPlaylistView: View {
    let song: MPMediaItem
    @Environment(\.dismiss) var dismiss
    @ObservedObject var playlistManager = PlaylistManager.shared
    
    @State private var showCreatePlaylist = false
    
    var body: some View {
        NavigationView {
            List {
                // create new playlist option
                Button(action: {
                    showCreatePlaylist = true
                }) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.pink.opacity(0.2))
                                .frame(width: 50, height: 50)
                            Image(systemName: "plus")
                                .font(.system(size: 22))
                                .foregroundColor(.pink)
                        }
                        
                        Text("New Playlist...")
                            .font(.system(size: 17))
                            .foregroundColor(.pink)
                    }
                }
                
                // existing playlists
                ForEach(playlistManager.playlists) { playlist in
                    Button(action: {
                        playlistManager.addSong(to: playlist.id, songID: song.persistentID)
                        dismiss()
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.gray)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)
                                Text("\(playlist.songPersistentIDs.count) songs")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistView()
            }
        }
    }
}
