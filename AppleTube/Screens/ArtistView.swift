import SwiftUI

/// Apple Music artist page: full-width hero image with the name over it, Top Songs, then album/playlist shelves.
struct ArtistView: View {
    let id: String
    let fallbackName: String

    @State private var detail: Loadable<ArtistDetail> = .loading

    var body: some View {
        ScrollView {
            switch detail {
            case .loading:
                LoadingView()
            case let .failed(message):
                ErrorView(message: message) { Task { await load() } }
            case let .loaded(artist):
                VStack(alignment: .leading, spacing: 28) {
                    hero(artist)
                    if !artist.songs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.songsSectionTitle ?? "Top Songs").font(.title2.bold()).padding(.horizontal)
                            ForEach(artist.songs.prefix(5)) { song in
                                SongRow(song: song) { WebPlayer.shared.play(song) }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                    ForEach(artist.orderedSections) { section in
                        let items = items(for: section)
                        if !items.isEmpty {
                            Shelf(title: section.title) {
                                ForEach(items) { ItemCard(item: $0, width: 150) }
                            }
                        }
                    }
                    if let description = artist.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About \(artist.artist.name)").font(.title2.bold())
                            Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(6)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func hero(_ artist: ArtistDetail) -> some View {
        ArtworkView(url: artist.artist.thumbnailURL, cornerRadius: 0, pixelSize: 1080)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom) {
                    Text(artist.artist.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                    Spacer()
                    if let first = artist.songs.first {
                        Button {
                            WebPlayer.shared.play(videoId: first.videoId, playlistId: "RDAMVM\(first.videoId)")
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.musicAccent, in: .circle)
                        }
                        .accessibilityLabel("Play \(artist.artist.name) station")
                    }
                }
                .padding()
                .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            }
    }

    private func items(for section: ArtistDetailSection) -> [HomeSectionItem] {
        switch section.content {
        case let .albums(albums): albums.map { .album($0) }
        case let .playlists(playlists): playlists.map { .playlist($0) }
        case let .artists(artists): artists.map { .artist($0) }
        default: []
        }
    }

    private func load() async {
        do {
            detail = .loaded(try await YTMusicAPI.shared.artist(id: id))
        } catch {
            detail = .failed(error.localizedDescription)
        }
    }
}
