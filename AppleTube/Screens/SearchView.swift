import SwiftUI

/// Apple Music search: live suggestions while typing, grouped results after submitting.
struct SearchView: View {
    @State private var query = ""
    @State private var suggestions: [SearchSuggestion] = []
    @State private var results: Loadable<SearchResponse>?

    var body: some View {
        NavigationStack {
            List {
                if let results {
                    switch results {
                    case .loading:
                        LoadingView().listRowSeparator(.hidden)
                    case let .failed(message):
                        ErrorView(message: message) { submit() }.listRowSeparator(.hidden)
                    case let .loaded(response):
                        SearchResults(response: response)
                    }
                } else if !query.isEmpty {
                    ForEach(suggestions) { suggestion in
                        Button {
                            query = suggestion.query
                            submit()
                        } label: {
                            Label(suggestion.query, systemImage: "magnifyingglass")
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    ContentUnavailableView("Search YouTube Music", systemImage: "magnifyingglass",
                                           description: Text("Artists, songs, albums and playlists."))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Artists, Songs, Lyrics, and More")
            .onSubmit(of: .search, submit)
            .task(id: query) {
                if case .loading = results { return }
                results = nil
                try? await Task.sleep(for: .milliseconds(200))
                suggestions = (try? await YTMusicAPI.shared.searchSuggestions(query)) ?? []
            }
            .musicDestinations()
            .task {
                // `-searchQuery <text>` runs a search on launch (screenshots/testing).
                if query.isEmpty, let text = UserDefaults.standard.string(forKey: "searchQuery") {
                    query = text
                    submit()
                }
            }
        }
    }

    private func submit() {
        let text = query
        guard !text.isEmpty else { return }
        results = .loading
        Task {
            do {
                results = .loaded(try await YTMusicAPI.shared.search(text))
            } catch {
                results = .failed(error.localizedDescription)
            }
        }
    }
}

private struct SearchResults: View {
    let response: SearchResponse

    var body: some View {
        if !response.artists.isEmpty {
            Section("Artists") {
                ForEach(response.artists.prefix(3)) { artist in
                    NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                        HStack(spacing: 12) {
                            ArtworkView(url: artist.thumbnailURL, isCircle: true, pixelSize: 160).frame(width: 56)
                            Text(artist.name)
                        }
                    }
                }
            }
        }
        if !response.songs.isEmpty {
            Section("Songs") {
                ForEach(response.songs.prefix(8)) { song in
                    SongRow(song: song, fallbackArtist: response.artists.first?.name) { AppState.shared.playAndShow(song) }
                }
            }
        }
        if !response.albums.isEmpty {
            Section("Albums") {
                ForEach(response.albums.prefix(6)) { album in
                    NavigationLink(value: Route.playlist(id: album.id, title: album.title)) {
                        resultRow(url: album.thumbnailURL, title: album.title, subtitle: ["Album", album.artistsDisplay, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }
            }
        }
        if !response.playlists.isEmpty {
            Section("Playlists") {
                ForEach(response.playlists.prefix(6)) { playlist in
                    NavigationLink(value: Route.playlist(id: playlist.id, title: playlist.title)) {
                        resultRow(url: playlist.thumbnailURL, title: playlist.title, subtitle: playlist.author?.name ?? "Playlist")
                    }
                }
            }
        }
    }

    private func resultRow(url: URL?, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: url, cornerRadius: 6, pixelSize: 160).frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
