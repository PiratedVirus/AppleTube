import SwiftUI

/// Apple Music "Radio": a grid of stations. YouTube Music's equivalent is its mixes (RD… playlists),
/// gathered from the home feed, plus "start a station" from songs you've been playing.
struct RadioView: View {
    @State private var stations: Loadable<[Playlist]> = .loading
    @State private var seeds: [Song] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                switch stations {
                case .loading:
                    LoadingView()
                case let .failed(message):
                    ErrorView(message: message) { Task { await load() } }
                case let .loaded(stations):
                    VStack(alignment: .leading, spacing: 28) {
                        if !stations.isEmpty {
                            Text("Your Stations").font(.title2.bold()).padding(.horizontal)
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(stations) { StationTile(playlist: $0) }
                            }
                            .padding(.horizontal)
                        }
                        if !seeds.isEmpty {
                            Shelf(title: "Start a Station") {
                                ForEach(seeds) { song in
                                    Button {
                                        WebPlayer.shared.play(videoId: song.videoId, playlistId: "RDAMVM\(song.videoId)")
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ArtworkView(url: song.thumbnailURL, isCircle: true).frame(width: 120)
                                            Text(song.title).font(.subheadline).lineLimit(1)
                                            Text(song.artistsDisplay).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .frame(width: 120, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Radio")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AccountButton() } }
            .musicDestinations()
            .refreshable { await load() }
            .task { if case .loading = stations { await load() } }
        }
    }

    private func load() async {
        do {
            var page = try await YTMusicAPI.shared.home()
            var sections = page.response.sections
            // Mixes are usually a few shelves down; pull a couple more pages.
            for _ in 0 ..< 2 {
                guard let token = page.continuation, let more = try? await YTMusicAPI.shared.homeContinuation(token) else { break }
                sections += more.sections
                page = (HomeResponse(sections: []), more.continuation)
            }
            var seen = Set<String>()
            let mixes = sections.flatMap(\.items).compactMap(\.playlist)
                .filter { ($0.id.hasPrefix("RD") || $0.id.hasPrefix("VLRD")) && seen.insert($0.id).inserted }
            seeds = Array(sections.flatMap(\.items).compactMap { if case let .song(song) = $0 { song } else { nil } }.prefix(12))
            stations = .loaded(mixes)
        } catch {
            stations = .failed(error.localizedDescription)
        }
    }
}

private struct StationTile: View {
    let playlist: Playlist

    var body: some View {
        Button {
            WebPlayer.shared.play(playlistId: playlist.id.hasPrefix("VL") ? String(playlist.id.dropFirst(2)) : playlist.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ArtworkView(url: playlist.thumbnailURL, cornerRadius: 10)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption.bold())
                            .padding(6)
                            .background(.ultraThinMaterial, in: .circle)
                            .padding(8)
                    }
                Text(playlist.title).font(.subheadline).lineLimit(1)
                if let description = playlist.description {
                    Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
