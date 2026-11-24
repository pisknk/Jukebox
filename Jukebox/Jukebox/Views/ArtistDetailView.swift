//
//  ArtistDetailView.swift
//  Jukebox
//
//  detail view for an artist showing their albums
//

import SwiftUI
import MediaPlayer

struct ArtistDetailView: View {
    let artistName: String
    @EnvironmentObject var musicManager: MusicPlayerManager

    /// loaded when the view appears, so building a list of artist links stays cheap
    @State private var artistAlbums: [MPMediaItemCollection] = []
    @State private var albumsLoaded = false
    @State private var artistImageURL: URL?
    @State private var isLoadingImage = true

    init(artistName: String) {
        self.artistName = artistName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // artist header
                VStack(spacing: 12) {
                    artistImageView

                    Text(artistName)
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(albumsLoaded ? "\(artistAlbums.count) albums" : " ")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                // albums section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Albums")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 20)

                    ForEach(artistAlbums, id: \.persistentID) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            HStack(spacing: 16) {
                                if let artwork = album.representativeItem?.artwork,
                                   let image = artwork.image(at: CGSize(width: 80, height: 80)) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .frame(width: 70, height: 70)
                                        .cornerRadius(6)
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 70, height: 70)
                                        Image(systemName: "square.stack")
                                            .foregroundColor(.gray)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(album.representativeItem?.albumTitle ?? "Unknown Album")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.primary)

                                    Text("\(album.count) songs")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                    }
                }

                Spacer(minLength: AppDesign.legacyBottomSpace(100))
            }
        }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !albumsLoaded {
                artistAlbums = LibraryQueries.albums(forArtist: artistName)
                albumsLoaded = true
            }
            loadArtistImage()
        }
    }

    // MARK: - artist image view

    @ViewBuilder
    private var artistImageView: some View {
        if let url = artistImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 160)
                        .clipShape(Circle())
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(width: 160, height: 160)
                @unknown default:
                    placeholderView
                }
            }
        } else if isLoadingImage {
            ProgressView()
                .frame(width: 160, height: 160)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 160, height: 160)

            Image(systemName: "music.mic")
                .font(.system(size: 50))
                .foregroundColor(.pink)
        }
    }

    // MARK: - load artist image

    private func loadArtistImage() {
        ArtistImageManager.shared.getArtistImage(name: artistName) { url in
            self.artistImageURL = url
            self.isLoadingImage = false
        }
    }
}
