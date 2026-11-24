//
//  PlaylistDetailView.swift
//  Jukebox
//
//  Detail view for a custom playlist with editing capabilities.
//

import SwiftUI
import MediaPlayer

struct PlaylistDetailView: View {
    let playlist: CustomPlaylist
    @EnvironmentObject var musicManager: MusicPlayerManager
    @ObservedObject var playlistManager = PlaylistManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showDeleteAlert = false
    @State private var shadowColor: Color = .black.opacity(0.3)
    @State private var showAddSongs = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var artistToShow: String?
    @State private var albumToShow: MPMediaItemCollection?
    
    /// songs on this device, each with its position in the saved playlist
    private var rows: [PlaylistRow] {
        playlistManager.rows(for: playlist.id, songsByID: musicManager.songsByID)
    }
    
    private var songs: [MPMediaItem] {
        rows.map(\.song)
    }
    
    private var title: String {
        currentPlaylist?.name ?? playlist.name
    }
    
    // get current playlist from manager (may be updated)
    private var currentPlaylist: CustomPlaylist? {
        playlistManager.playlists.first { $0.id == playlist.id }
    }
    
    var body: some View {
        List {
            // Section 1: Header (Artwork, Name, Controls)
            Section {
                VStack(spacing: 20) {
                    // playlist artwork
                    ZStack {
                        if let img = selectedImage ?? currentPlaylist.flatMap({ playlistManager.coverImage(for: $0, songsByID: musicManager.songsByID) }) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 220, height: 220)
                                .cornerRadius(8)
                                .shadow(color: shadowColor, radius: 25, x: 0, y: 8)
                                .onAppear {
                                    // extract color for shadow
                                    DispatchQueue.global(qos: .userInteractive).async {
                                        let colors = img.extractDominantColors(count: 1)
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
                                    .fill(LinearGradient(
                                        colors: [.pink.opacity(0.4), .purple.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 220, height: 220)
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // edit overlay
                        if isEditing {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 220, height: 220)
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                    Text("Change Cover")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .onTapGesture {
                                showImagePicker = true
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // playlist name
                    if isEditing {
                        TextField("Playlist Name", text: $editedName)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 40)
                    } else {
                        Text(currentPlaylist?.name ?? playlist.name)
                            .font(.system(size: 22, weight: .bold))
                    }
                    
                    Text("\(songs.count) songs")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    
                    // play / shuffle buttons
                    if !songs.isEmpty {
                        HStack(spacing: 16) {
                            Button(action: {
                                musicManager.playInOrder(songs: songs, context: title)
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
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                musicManager.playShuffled(songs: songs, context: title)
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
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // add songs button in edit mode
                    if isEditing {
                        Button(action: { showAddSongs = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Songs")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pink)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.bottom, 20)
                .background(Color(UIColor.systemBackground))
            }
            
            // Section 2: Song List
            Section {
                if songs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No songs yet")
                            .foregroundColor(.secondary)
                        Text("Add songs from your library")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        Button(action: { showAddSongs = true }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Songs")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.pink)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(rows) { row in
                        let song = row.song
                        HStack(spacing: 12) {
                            // artwork
                            if let artwork = song.artwork,
                               let image = artwork.image(at: CGSize(width: 50, height: 50)) {
                                Image(uiImage: image)
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(4)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "music.note")
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title ?? "Unknown")
                                    .font(.system(size: 16))
                                    .lineLimit(1)
                                Text(song.artist ?? "Unknown Artist")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isEditing {
                                musicManager.play(songs: songs, startWith: song, context: title)
                            }
                        }
                        .contextMenu {
                            Button {
                                musicManager.addToQueue(song: song)
                            } label: {
                                Label("Add to Queue", systemImage: "text.badge.plus")
                            }
                            
                            if let artist = song.artist {
                                Button {
                                    artistToShow = artist
                                } label: {
                                    Label("Go to \(artist)", systemImage: "person.fill")
                                }
                            }
                            
                            if let album = song.albumTitle {
                                Button {
                                    albumToShow = LibraryQueries.album(containing: song)
                                } label: {
                                    Label("Go to \(album)", systemImage: "square.stack")
                                }
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                playlistManager.removeSongs(from: playlist.id, storedIndices: IndexSet(integer: row.storedIndex))
                            } label: {
                                Label("Remove from Playlist", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        // offsets are positions on screen; translate to the saved list
                        let stored = PlaylistOrdering.storedOffsets(forVisible: offsets, visibleIndices: rows.map(\.storedIndex))
                        playlistManager.removeSongs(from: playlist.id, storedIndices: stored)
                    }
                    .onMove { source, destination in
                        playlistManager.moveVisibleSongs(in: playlist.id, rows: rows, from: source, to: destination)
                    }
                }
            }
            
            // bottom spacer for tab bar + mini player
            Section {
                Color.clear
                    .frame(height: 100)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        // save name (ignored if blank)
                        playlistManager.renamePlaylist(id: playlist.id, name: editedName)
                        // save cover image
                        if let image = selectedImage {
                            playlistManager.setCoverImage(image, for: playlist.id)
                            selectedImage = nil
                        }
                    } else {
                        editedName = currentPlaylist?.name ?? playlist.name
                    }
                    withAnimation {
                        isEditing.toggle()
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showAddSongs = true }) {
                        Label("Add Songs", systemImage: "plus")
                    }
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Playlist?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                playlistManager.deletePlaylist(id: playlist.id)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showAddSongs) {
            AddSongsToPlaylistView(playlistID: playlist.id)
                .environmentObject(musicManager)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(item: $albumToShow) { album in
            NavigationView {
                AlbumDetailView(album: album)
                    .environmentObject(musicManager)
            }
        }
        .sheet(isPresented: Binding(
            get: { artistToShow != nil },
            set: { if !$0 { artistToShow = nil } }
        )) {
            if let artist = artistToShow {
                NavigationView {
                    ArtistDetailView(artistName: artist)
                        .environmentObject(musicManager)
                }
            }
        }
    }
}

// MARK: - Add Songs to Playlist View (Multi-Select)
struct AddSongsToPlaylistView: View {
    let playlistID: UUID
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var musicManager: MusicPlayerManager
    @ObservedObject var playlistManager = PlaylistManager.shared
    
    @State private var searchText = ""
    @State private var selectedSongs: Set<UInt64> = []
    
    private var currentPlaylist: CustomPlaylist? {
        playlistManager.playlists.first { $0.id == playlistID }
    }
    
    private var filteredSongs: [MPMediaItem] {
        let existing = Set(currentPlaylist?.songPersistentIDs ?? [])
        let available = musicManager.songs.filter { !existing.contains($0.persistentID) }
        
        if searchText.isEmpty { return available }
        return available.filter { song in
            (song.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (song.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // search bar
                SearchBar(text: $searchText, placeholder: "Search songs...")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                List {
                    ForEach(filteredSongs, id: \.persistentID) { song in
                        HStack(spacing: 12) {
                            // checkbox
                            Image(systemName: selectedSongs.contains(song.persistentID) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selectedSongs.contains(song.persistentID) ? .pink : .gray)
                            
                            // artwork
                            if let artwork = song.artwork,
                               let image = artwork.image(at: CGSize(width: 50, height: 50)) {
                                Image(uiImage: image)
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(4)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "music.note")
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title ?? "Unknown")
                                    .font(.system(size: 16))
                                    .lineLimit(1)
                                Text(song.artist ?? "Unknown Artist")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedSongs.contains(song.persistentID) {
                                selectedSongs.remove(song.persistentID)
                            } else {
                                selectedSongs.insert(song.persistentID)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedSongs.count))") {
                        // add in library order, not the random order of a set
                        let ordered = musicManager.songs
                            .map(\.persistentID)
                            .filter { selectedSongs.contains($0) }
                        playlistManager.addSongs(to: playlistID, songIDs: ordered)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedSongs.isEmpty)
                }
            }
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let edited = info[.editedImage] as? UIImage {
                parent.image = edited
            } else if let original = info[.originalImage] as? UIImage {
                parent.image = original
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
