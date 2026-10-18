import SwiftUI

/// Apple Music "Library": category rows (Playlists, Artists, Albums, Songs) then a "Recently Added" grid.
struct LibraryView: View {
    @State private var app = AppState.shared
    @State private var content: Loadable<PlaylistParser.LibraryContent> = .loading
    @State private var playlists: [Playlist] = []

    var body: some View {
        NavigationStack {
            Group {
                if app.signedIn == nil {
                    ProgressView()
                } else if app.signedIn == false {
                    ContentUnavailableView {
                        Label("Sign In to See Your Library", systemImage: "music.note.house")
                    } description: {
                        Text("Your YouTube Music playlists, albums and artists appear here.")
                    } actions: {
                        Button("Sign In") { app.isAccountPresented = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    library
                }
            }
            .navigationTitle("Library")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AccountButton() } }
            .musicDestinations()
            .navigationDestination(for: LibraryCategory.self) { LibraryCategoryView(category: $0, content: loadedContent, playlists: playlists) }
            .task(id: app.signedIn) { if app.signedIn == true { await load() } }
        }
    }

    private var loadedContent: PlaylistParser.LibraryContent? {
        if case let .loaded(content) = content { content } else { nil }
    }

    private var library: some View {
        List {
            Section {
                ForEach(LibraryCategory.allCases) { category in
                    NavigationLink(value: category) {
                        Label(category.title, systemImage: category.symbol)
                            .font(.title3)
                            .labelStyle(LibraryRowLabelStyle())
                    }
                }
            }
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                switch content {
                case .loading:
                    LoadingView().listRowSeparator(.hidden)
                case let .failed(message):
                    ErrorView(message: message) { Task { await load() } }.listRowSeparator(.hidden)
                case .loaded:
                    RecentlyAddedGrid(playlists: playlists, albums: loadedContent?.albums ?? [])
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text("Recently Added").font(.title2.bold()).foregroundStyle(.primary).textCase(nil)
            }
        }
        .listStyle(.plain)
        .refreshable { await load() }
    }

    private func load() async {
        do {
            async let landing = YTMusicAPI.shared.libraryLanding()
            async let lists = YTMusicAPI.shared.libraryPlaylists()
            let (content, playlists) = try await (landing, lists)
            self.playlists = playlists.isEmpty ? content.playlists : playlists
            self.content = .loaded(content)
        } catch {
            content = .failed(error.localizedDescription)
        }
    }
}

enum LibraryCategory: String, CaseIterable, Identifiable, Hashable {
    case playlists, artists, albums, songs
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.microphone"
        case .albums: "square.stack"
        case .songs: "music.note"
        }
    }
}

private struct LibraryRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon.foregroundStyle(Color.musicAccent).frame(width: 28)
            configuration.title
        }
        .padding(.vertical, 6)
    }
}

private struct RecentlyAddedGrid: View {
    let playlists: [Playlist]
    let albums: [Album]
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let items: [HomeSectionItem] = albums.map { .album($0) } + playlists.map { .playlist($0) }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(items.prefix(20)) { item in
                if let route = item.route {
                    NavigationLink(value: route) {
                        VStack(alignment: .leading, spacing: 4) {
                            ArtworkView(url: item.thumbnailURL).zoomSource(for: item.route)
                            Text(item.title).font(.subheadline).lineLimit(1)
                            if let subtitle = item.homeCardSubtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One library category as a list, Apple Music style.
private struct LibraryCategoryView: View {
    let category: LibraryCategory
    let content: PlaylistParser.LibraryContent?
    let playlists: [Playlist]

    var body: some View {
        List {
            switch category {
            case .playlists:
                ForEach(playlists) { playlist in
                    NavigationLink(value: Route.playlist(id: playlist.id, title: playlist.title)) {
                        row(url: playlist.thumbnailURL, title: playlist.title, subtitle: playlist.author?.name)
                    }
                }
            case .artists:
                ForEach(content?.artists ?? []) { artist in
                    NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                        row(url: artist.thumbnailURL, title: artist.name, subtitle: nil, circle: true)
                    }
                }
            case .albums:
                ForEach(content?.albums ?? []) { album in
                    NavigationLink(value: Route.playlist(id: album.id, title: album.title)) {
                        row(url: album.thumbnailURL, title: album.title, subtitle: album.artistsDisplay)
                    }
                }
            case .songs:
                // Liked songs are YouTube Music's "LM" playlist.
                NavigationLink(value: Route.playlist(id: LikedMusicPlaylist.id, title: "Liked Songs")) {
                    Label("Liked Songs", systemImage: "heart.fill").foregroundStyle(Color.musicAccent)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
    }

    private func row(url: URL?, title: String, subtitle: String?, circle: Bool = false) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: url, cornerRadius: 6, isCircle: circle, pixelSize: 160).frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}
