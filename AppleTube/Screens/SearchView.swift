import SwiftUI

/// Apple Music search: Recently Searched (with Clear) and Browse when idle, live suggestions while typing,
/// and one ranked result list labelled "Song · Artist", "Album · Artist"… after submitting. The scope picker
/// switches between all of YouTube Music and your own library.
struct SearchView: View {
    enum Scope: String, CaseIterable { case catalog = "YouTube Music", library = "Library" }

    @State private var query = ""
    @State private var scope = Scope.catalog
    @State private var suggestions: [SearchSuggestion] = []
    @State private var results: Loadable<SearchResponse>?
    @State private var recents = RecentSearches.shared
    @State private var browse: [HomeSection] = []
    @State private var library: PlaylistParser.LibraryContent?
    @State private var libraryPlaylists: [Playlist] = []
    @State private var app = AppState.shared
    @FocusState private var isSearchFocused: Bool
    @State private var submittedQuery: String?

    private var isIdle: Bool { query.isEmpty && results == nil }

    var body: some View {
        NavigationStack {
            Group {
                if isIdle {
                    // ScrollView, not List: shelf rows hold many links and a List row fires them all on one tap.
                    ScrollView { idleContent.padding(.bottom, 100) }
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Artists, Songs, Lyrics and More")
            .searchFocused($isSearchFocused)
            // Tapping the Search tab again puts the cursor straight in the field.
            .onChange(of: app.searchFocusRequest) { _, _ in isSearchFocused = true }
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .onSubmit(of: .search, submit)
            .task(id: query) {
                // This task also re-runs when the screen reappears (e.g. Back from an artist); keep the results
                // unless the text actually changed since the search was submitted.
                if query == submittedQuery, results != nil { return }
                results = nil
                guard scope == .catalog else { return }
                try? await Task.sleep(for: .milliseconds(200))
                suggestions = (try? await YTMusicAPI.shared.searchSuggestions(query)) ?? []
            }
            .task(id: scope) {
                guard scope == .library, library == nil, AppState.shared.signedIn == true else { return }
                async let content = try? YTMusicAPI.shared.libraryLanding()
                async let playlists = try? YTMusicAPI.shared.libraryPlaylists()
                (library, libraryPlaylists) = await (content, playlists ?? [])
            }
            .task {
                browse = (try? await YTMusicAPI.shared.explore())?
                    .map { HomeSection(id: $0.id, title: $0.title, items: $0.items.filter { $0.thumbnailURL != nil }, isChart: $0.isChart) }
                    .filter { !$0.items.isEmpty } ?? []
                // `-searchQuery <text>` runs a search on launch (screenshots/testing).
                if query.isEmpty, let text = UserDefaults.standard.string(forKey: "searchQuery") {
                    query = text
                    submit()
                }
            }
            .musicDestinations()
        }
    }

    private var resultsList: some View {
        List {
            if scope == .library, !query.isEmpty {
                LibraryResults(query: query, content: library, playlists: libraryPlaylists)
            } else if let results {
                switch results {
                case .loading:
                    LoadingView().listRowSeparator(.hidden)
                case let .failed(message):
                    ErrorView(message: message) { submit() }.listRowSeparator(.hidden)
                case let .loaded(response):
                    ForEach(response.allItems.prefix(40)) { item in
                        ResultRow(item: item, fallbackArtist: response.artists.first?.name)
                    }
                }
            } else if !query.isEmpty {
                ForEach(suggestions) { suggestion in
                    Button {
                        query = suggestion.query
                        submit()
                    } label: {
                        Label(suggestion.query, systemImage: "magnifyingglass").foregroundStyle(.primary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !recents.items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recently Searched").font(.title3.bold())
                        Spacer()
                        Button("Clear") { withAnimation { recents.clear() } }
                            .foregroundStyle(Color.musicAccent)
                    }
                    .padding(.bottom, 8)
                    ForEach(recents.items) { item in
                        RecentRow(item: item)
                            .padding(.vertical, 6)
                            .contextMenu {
                                Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { recents.remove(item) } }
                            }
                        Divider().padding(.leading, 68)
                    }
                }
                .padding(.horizontal)
            }
            ForEach(browse) { section in
                Shelf(title: section.title) {
                    ForEach(section.items) { ItemCard(item: $0, width: 150) }
                }
            }
        }
        .padding(.top, 8)
    }

    private func submit() {
        let text = query
        guard !text.isEmpty, scope == .catalog else { return }
        submittedQuery = text
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

/// One search result in Apple's style: artwork, title, and "Kind · Artist". Songs play and open Now Playing.
private struct ResultRow: View {
    let item: SearchResultItem
    let fallbackArtist: String?

    var body: some View {
        switch item {
        case let .song(song), let .video(song):
            SongRow(song: song, fallbackArtist: fallbackArtist, kind: { if case .video = item { "Video" } else { "Song" } }()) {
                RecentSearches.shared.add(.init(song: song, fallbackArtist: fallbackArtist))
                AppState.shared.playAndShow(song)
            }
        case let .album(album), let .audiobook(album):
            link(.playlist(id: album.id, title: album.title, artwork: album.thumbnailURL), url: album.thumbnailURL, title: album.title,
                 subtitle: ["Album", album.artistsDisplay].filter { !$0.isEmpty }.joined(separator: " · "))
                .contextMenu { ItemMenu(item: .album(album)) }
        case let .artist(artist), let .profile(artist):
            link(.artist(id: artist.id, name: artist.name), url: artist.thumbnailURL, title: artist.name, subtitle: "Artist", circle: true)
                .contextMenu { ArtistMenu(artist: artist) }
        case let .playlist(playlist):
            link(.playlist(id: playlist.id, title: playlist.title, artwork: playlist.thumbnailURL), url: playlist.thumbnailURL, title: playlist.title,
                 subtitle: ["Playlist", playlist.author?.name].compactMap { $0 }.joined(separator: " · "))
                .contextMenu { ItemMenu(item: .playlist(playlist)) }
        default:
            EmptyView()
        }
    }

    private func link(_ route: Route, url: URL?, title: String, subtitle: String, circle: Bool = false) -> some View {
        NavigationLink(value: route) {
            ResultLabel(url: url, title: title, subtitle: subtitle, circle: circle)
        }
        .simultaneousGesture(TapGesture().onEnded {
            RecentSearches.shared.add(.init(route: route, title: title, subtitle: subtitle, artworkURL: url, circle: circle))
        })
    }
}

private struct ResultLabel: View {
    let url: URL?
    let title: String
    let subtitle: String
    var circle = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: url, cornerRadius: 6, isCircle: circle, pixelSize: 160).frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct RecentRow: View {
    let item: RecentSearches.Item

    var body: some View {
        if let videoId = item.videoId {
            Button {
                WebPlayer.shared.play(videoId: videoId, playlistId: nil)
                AppState.shared.isNowPlayingPresented = true
            } label: {
                HStack {
                    ResultLabel(url: item.artworkURL, title: item.title, subtitle: item.subtitle)
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else if let route = item.route {
            NavigationLink(value: route) {
                ResultLabel(url: item.artworkURL, title: item.title, subtitle: item.subtitle, circle: item.isCircle)
            }
        }
    }
}

/// Library scope: your playlists, albums and artists whose names match.
private struct LibraryResults: View {
    let query: String
    let content: PlaylistParser.LibraryContent?
    let playlists: [Playlist]

    var body: some View {
        let match = { (text: String) in text.localizedCaseInsensitiveContains(query) }
        if AppState.shared.signedIn != true {
            ContentUnavailableView("Sign In to Search Your Library", systemImage: "music.note.house").listRowSeparator(.hidden)
        } else if content == nil {
            LoadingView().listRowSeparator(.hidden)
        } else {
            ForEach(playlists.filter { match($0.title) }) { playlist in
                NavigationLink(value: Route.playlist(id: playlist.id, title: playlist.title, artwork: playlist.thumbnailURL)) {
                    ResultLabel(url: playlist.thumbnailURL, title: playlist.title, subtitle: "Playlist")
                }
            }
            ForEach((content?.albums ?? []).filter { match($0.title) || match($0.artistsDisplay) }) { album in
                NavigationLink(value: Route.playlist(id: album.id, title: album.title, artwork: album.thumbnailURL)) {
                    ResultLabel(url: album.thumbnailURL, title: album.title, subtitle: "Album · \(album.artistsDisplay)")
                }
            }
            ForEach((content?.artists ?? []).filter { match($0.name) }) { artist in
                NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                    ResultLabel(url: artist.thumbnailURL, title: artist.name, subtitle: "Artist", circle: true)
                }
            }
        }
    }
}

/// Things you opened from search, newest first, kept on the device.
@MainActor
@Observable
final class RecentSearches {
    static let shared = RecentSearches()

    struct Item: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var subtitle: String
        var artworkURL: URL?
        var videoId: String?
        var playlistId: String?
        var artistId: String?
        var isCircle = false

        var route: Route? {
            if let playlistId { return .playlist(id: playlistId, title: title, artwork: artworkURL) }
            if let artistId { return .artist(id: artistId, name: title) }
            return nil
        }

        init(song: Song, fallbackArtist: String?) {
            let artist = song.artistsDisplay.isEmpty ? (fallbackArtist ?? "") : song.artistsDisplay
            id = "song:\(song.videoId)"
            title = song.title
            subtitle = ["Song", artist].filter { !$0.isEmpty }.joined(separator: " · ")
            artworkURL = song.thumbnailURL
            videoId = song.videoId
        }

        init(route: Route, title: String, subtitle: String, artworkURL: URL?, circle: Bool) {
            self.title = title
            self.subtitle = subtitle
            self.artworkURL = artworkURL
            isCircle = circle
            switch route {
            case let .playlist(id, _, _):
                self.id = "playlist:\(id)"
                playlistId = id
            case let .artist(id, _):
                self.id = "artist:\(id)"
                artistId = id
            }
        }
    }

    private(set) var items: [Item] = []
    private let key = "recentSearches"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func add(_ item: Item) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > 30 { items.removeLast(items.count - 30) }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }
}
